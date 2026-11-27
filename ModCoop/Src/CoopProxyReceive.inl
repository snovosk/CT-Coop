// Capture authoritative movement before APawn's prediction-error correction.
// Context exists only on the receive call stack: no actor pointers survive it.
typedef void (__fastcall* FProxyReceiveFunction)(APawn*, DWORD);
struct FProxyReceiveHooks
{
    void** Table;
    FProxyReceiveFunction Receive, Location;
};
static TArray<FProxyReceiveHooks> ProxyReceiveHooks;
static INT ProxyReceiveSlot = -1, ProxyLocationSlot = -1, ProxyReceiveSequence = 0;
static FVector* ProxyIncomingLocation = NULL;
static void* EnginePawnReceive = NULL;
static void* EnginePawnReceiveLocation = NULL;

struct FProxyReceiveContext
{
    FProxyReceiveContext* Previous;
    APawn* Pawn;
    FVector Position, Velocity;
    INT Sequence;
    UBOOL HasMovement, Consumed;
};
static FProxyReceiveContext* ActiveProxyReceive = NULL;
struct FScopedProxyReceive : FProxyReceiveContext
{
    explicit FScopedProxyReceive(APawn* InPawn)
    {
        Previous=ActiveProxyReceive; Pawn=InPawn;
        HasMovement=0; Consumed=0; Sequence=0;
        ActiveProxyReceive=this;
    }
    ~FScopedProxyReceive() { ActiveProxyReceive=Previous; }
};

static FProxyReceiveHooks* FindProxyReceiveHooks(APawn* Pawn)
{
    void** Table = *reinterpret_cast<void***>(Pawn);
    for(INT i=0; i<ProxyReceiveHooks.Num(); ++i)
        if(ProxyReceiveHooks[i].Table==Table) return &ProxyReceiveHooks[i];
    return NULL;
}

static void* ResolveProxyThunk(void* Address)
{
    for(INT i=0; Address && i<4; ++i)
    {
        BYTE* Code = static_cast<BYTE*>(Address);
        if(Code[0]==0xE9) Address=Code+5+*reinterpret_cast<INT*>(Code+1);
        else if(Code[0]==0xFF && Code[1]==0x25)
            Address=**reinterpret_cast<void***>(Code+2);
        else break;
    }
    return Address;
}

static void __fastcall ProxyReceiveOverride(APawn* Pawn, DWORD Edx)
{
    FProxyReceiveFunction Original=FindProxyReceiveHooks(Pawn)->Receive;
    FScopedProxyReceive Context(Pawn);
    Original(Pawn,Edx); // Includes PostNetworkReceive, where script reads Context.
    // A new proxy can receive its first position before script enables
    // bNetNotify. Deliver that position as well, while the scoped data is valid.
    if(Context.HasMovement && !Context.Consumed && !Pawn->bDeleteMe)
    {
        APlayerController* Player=Pawn->Level->GetLocalPlayerController();
        UFunction* Function=Player ? Player->FindFunction(FName("ProxyNetworkReceived",FNAME_Find)) : NULL;
        if(Function)
        {
            struct { APawn* P; } Params={Pawn};
            Player->ProcessEvent(Function,&Params);
        }
    }
}

static void __fastcall ProxyReceiveLocationOverride(APawn* Pawn, DWORD Edx)
{
    FProxyReceiveFunction Original=FindProxyReceiveHooks(Pawn)->Location;
    FProxyReceiveContext* Context=ActiveProxyReceive;
    if(Context && Context->Pawn==Pawn && Pawn->Level &&
       Pawn->Level->NetMode==NM_Client && Pawn->Role==ROLE_SimulatedProxy)
    {
        Context->Position=*ProxyIncomingLocation;
        Context->Velocity=Pawn->Velocity;
        if(ProxyReceiveSequence>=0x7FFFFFFE) ProxyReceiveSequence=1;
        else ++ProxyReceiveSequence;
        Context->Sequence=ProxyReceiveSequence;
        Context->HasMovement=1;
    }
    Original(Pawn,Edx); // Preserve physics, collision and the native corrections.
}

static UBOOL VerifyProxyReceiveLayout()
{
    static INT Checked=0;
    if(Checked) return Checked>0;
    Checked=-1;
    HMODULE Engine=GetModuleHandleA("Engine.dll");
    if(!Engine) return 0;
    EnginePawnReceive=GetProcAddress(Engine,"?PostNetReceive@APawn@@UAEXXZ");
    EnginePawnReceiveLocation=GetProcAddress(Engine,"?PostNetReceiveLocation@APawn@@UAEXXZ");
    BYTE* ActorReceive=reinterpret_cast<BYTE*>(GetProcAddress(Engine,"?PostNetReceive@AActor@@UAEXXZ"));
    void** PawnTable=reinterpret_cast<void**>(GetProcAddress(Engine,"??_7APawn@@6B@"));
    BYTE* Location=static_cast<BYTE*>(EnginePawnReceiveLocation);
    if(!EnginePawnReceive || !Location || !ActorReceive || !PawnTable) return 0;
    // Verified build-139 instruction signatures. Derive relocated scratch
    // address from operands, never assume the module's preferred load address.
    const BYTE Prefix[]={0x83,0xEC,0x58,0x56,0x8B,0xF1};
    if(memcmp(Location,Prefix,sizeof(Prefix)) || Location[0x78]!=0x68 ||
       ActorReceive[0x23]!=0x8B || ActorReceive[0x24]!=0x3D) return 0;
    DWORD Scratch=*reinterpret_cast<DWORD*>(Location+0x79);
    if(Scratch!=*reinterpret_cast<DWORD*>(ActorReceive+0x25)) return 0;
    IMAGE_DOS_HEADER* Dos=reinterpret_cast<IMAGE_DOS_HEADER*>(Engine);
    IMAGE_NT_HEADERS* Nt=reinterpret_cast<IMAGE_NT_HEADERS*>(reinterpret_cast<BYTE*>(Engine)+Dos->e_lfanew);
    DWORD Start=reinterpret_cast<DWORD>(Engine);
    if(Scratch<Start || Scratch+sizeof(FVector)>Start+Nt->OptionalHeader.SizeOfImage) return 0;
    UProperty* Loc=FindField<UProperty>(AActor::StaticClass(),"Location");
    UProperty* Vel=FindField<UProperty>(AActor::StaticClass(),"Velocity");
    if(!Loc || !Vel || Loc->Offset!=offsetof(AActor,Location) || Vel->Offset!=offsetof(AActor,Velocity)) return 0;
    for(INT i=0;i<128;++i)
    {
        if(PawnTable[i]==EnginePawnReceive) ProxyReceiveSlot=i;
        if(PawnTable[i]==EnginePawnReceiveLocation) ProxyLocationSlot=i;
    }
    if(ProxyReceiveSlot<0 || ProxyLocationSlot<0) return 0;
    ProxyIncomingLocation=reinterpret_cast<FVector*>(Scratch);
    Checked=1;
    debugf("ModCoop: Verified raw proxy receive layout (slots %i/%i)",ProxyReceiveSlot,ProxyLocationSlot);
    return 1;
}

static UBOOL InstallProxyTable(void** Table, const TCHAR* Label)
{
    if(!Table || !VerifyProxyReceiveLayout()) return 0;
    for(INT i=0;i<ProxyReceiveHooks.Num();++i)
        if(ProxyReceiveHooks[i].Table==Table) return 1;
    // Native subclasses with a different receive implementation are left alone.
    if(ResolveProxyThunk(Table[ProxyReceiveSlot])!=EnginePawnReceive ||
       ResolveProxyThunk(Table[ProxyLocationSlot])!=EnginePawnReceiveLocation) return 0;
    FProxyReceiveHooks Entry;
    Entry.Table=Table;
    Entry.Receive=reinterpret_cast<FProxyReceiveFunction>(Table[ProxyReceiveSlot]);
    Entry.Location=reinterpret_cast<FProxyReceiveFunction>(Table[ProxyLocationSlot]);
    if(!PatchVTable(&Table,ProxyReceiveSlot,ProxyReceiveOverride)) return 0;
    if(!PatchVTable(&Table,ProxyLocationSlot,ProxyReceiveLocationOverride))
    { PatchVTable(&Table,ProxyReceiveSlot,Entry.Receive); return 0; }
    ProxyReceiveHooks.AddItem(Entry);
    debugf("ModCoop: Raw movement receiver installed for %s",Label);
    return 1;
}

static void InstallProxyReceiveDefaults()
{
    HMODULE Engine=GetModuleHandleA("Engine.dll"), CTGame=GetModuleHandleA("CTGame.dll");
    if(Engine) InstallProxyTable(reinterpret_cast<void**>(GetProcAddress(Engine,"??_7APawn@@6B@")),"Engine.Pawn");
    if(CTGame) InstallProxyTable(reinterpret_cast<void**>(GetProcAddress(CTGame,"??_7ACTPawn@@6B@")),"CTGame.CTPawn");
}

void UCoopNative::execInstallProxyReceiver(FFrame& Stack, void* Result)
{
    P_GET_OBJECT(APawn,Pawn);
    P_FINISH;
    *static_cast<UBOOL*>(Result)=Pawn && Pawn->Level && Pawn->Level->NetMode==NM_Client &&
        InstallProxyTable(*reinterpret_cast<void***>(Pawn),Pawn->GetClass()->GetName());
}

void UCoopNative::execReadProxyMovement(FFrame& Stack, void* Result)
{
    P_GET_OBJECT(APawn,Pawn);
    P_GET_VECTOR_REF(Position);
    P_GET_VECTOR_REF(Velocity);
    P_GET_INT_REF(Sequence);
    P_FINISH;
    *static_cast<UBOOL*>(Result)=0;
    FProxyReceiveContext* Context=ActiveProxyReceive;
    if(!Context || Context->Pawn!=Pawn || !Context->HasMovement || Context->Consumed) return;
    *Position=Context->Position; *Velocity=Context->Velocity; *Sequence=Context->Sequence;
    Context->Consumed=1;
    *static_cast<UBOOL*>(Result)=1;
}
