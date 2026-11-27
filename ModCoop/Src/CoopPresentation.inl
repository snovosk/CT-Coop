// Engine Draw scope: this game does not dispatch HUD.PreRender. UnrealScript
// retains GC-visible pawn references; only this stack scope keeps the
// current viewport's controller while the chained Draw call is running.
typedef void (__fastcall* FPresentationDraw)(UGameEngine*, DWORD, UViewport*, INT, BYTE*, INT*);
static FPresentationDraw OriginalPresentationDraw=NULL;
static INT PresentationDrawDepth=0;
struct FPresentationDrawScope
{
    APlayerController* Player;
    UFunction* End;

    explicit FPresentationDrawScope(UViewport* View):Player(NULL),End(NULL)
    {
        ++PresentationDrawDepth;
        if(PresentationDrawDepth!=1 || !View || !View->Actor || !View->Actor->Level) return;
        APlayerController* PC=View->Actor;
        if(PC->Level->NetMode!=NM_Client) return;
        UFunction* Begin=PC->FindFunction(FName("BeginProxyRender",FNAME_Find));
        UFunction* Finish=PC->FindFunction(FName("EndProxyRender",FNAME_Find));
        if(!Begin || !Finish) return;
        Player=PC;
        End=Finish;
        Player->ProcessEvent(Begin,NULL);
    }

    ~FPresentationDrawScope()
    {
        if(Player && !Player->bDeleteMe) Player->ProcessEvent(End,NULL);
        --PresentationDrawDepth;
    }
};

static void __fastcall PresentationDrawOverride(UGameEngine* Engine,DWORD Edx,UViewport* View,INT Blit,BYTE* Hit,INT* HitSize)
{
    FPresentationDrawScope Scope(View);
    OriginalPresentationDraw(Engine,Edx,View,Blit,Hit,HitSize);
}

static void InstallPresentationDraw()
{
    if(OriginalPresentationDraw) return;
    UProperty* Actor=FindField<UProperty>(UPlayer::StaticClass(),TEXT("Actor"));
    if(!Actor || Actor->Offset!=offsetof(UPlayer,Actor)) return;
    HMODULE Engine=GetModuleHandleA("Engine.dll");
    if(!Engine) return;
    void** Table=reinterpret_cast<void**>(GetProcAddress(Engine,"??_7UGameEngine@@6BUObject@@@"));
    // SWRCFix has already replaced the derived Draw slot. Resolve its index
    // from the unmodified base table and chain the current derived entry so
    // its FOV and reticle fixes remain active.
    void** Base=reinterpret_cast<void**>(GetProcAddress(Engine,"??_7UEngine@@6BUObject@@@"));
    void* Draw=GetProcAddress(Engine,"?Draw@UEngine@@UAEXPAVUViewport@@HPAEPAH@Z");
    if(!Table || !Base || !Draw) return;
    for(INT i=0;i<128;++i)
        if(Base[i]==Draw)
        {
            OriginalPresentationDraw=PatchVTable(&Table,i,PresentationDrawOverride);
            debugf("ModCoop: Installed scoped presentation draw (%i)",i);
            return;
        }
    debugf(NAME_Warning,"ModCoop: Presentation draw unavailable; retaining native facing");
}

static UBOOL ValidPresentationPawn(APawn* P)
{
    return P && !P->bDeleteMe && P->Level && P->Level->NetMode==NM_Client &&
        P->Role==ROLE_SimulatedProxy;
}

void UCoopNative::execSetProxyRenderFacing(FFrame& Stack, void* Result)
{
    P_GET_OBJECT(APawn,P);
    P_GET_ROTATOR(Facing);
    P_FINISH;
    *static_cast<UBOOL*>(Result)=ValidPresentationPawn(P);
    // Avoid MoveActor/SetRotation collision and attachment side effects. The
    // authoritative client rotation is restored immediately after world draw.
    if(*static_cast<UBOOL*>(Result)) P->Rotation=Facing;
}

typedef void (__fastcall* FUpdateLocomotion)(APawn*, DWORD, FLOAT);
static FUpdateLocomotion PresentationLocomotion=NULL;
static UBOOL VerifyPresentationLayout()
{
    static INT Checked=0;
    if(Checked) return Checked>0;
    Checked=-1;
    struct Field { const TCHAR* Name; INT Offset; } Fields[]={
        {TEXT("Velocity"),offsetof(APawn,Velocity)}, {TEXT("Acceleration"),offsetof(APawn,Acceleration)},
        {TEXT("Rotation"),offsetof(APawn,Rotation)}, {TEXT("CurrentIdleState"),offsetof(APawn,CurrentIdleState)}
        ,{TEXT("DesiredRotation"),offsetof(APawn,DesiredRotation)}, {TEXT("RotationRate"),offsetof(APawn,RotationRate)}
    };
    for(INT i=0;i<ARRAY_COUNT(Fields);++i)
    {
        UProperty* P=FindField<UProperty>(APawn::StaticClass(),Fields[i].Name);
        if(!P || P->Offset!=Fields[i].Offset) return 0;
    }
    // Walking/crouch flags share the verified build-139 pawn flag word.
    const TCHAR* Names[]={TEXT("bIsWalking"),TEXT("bIsCrouched"),TEXT("bPhysicsAnimUpdate")};
    DWORD Masks[]={1,4,512};
    for(INT i=0;i<3;++i)
    {
        UBoolProperty* P=FindField<UBoolProperty>(APawn::StaticClass(),Names[i]);
        if(!P || P->Offset!=644 || (1u<<P->BitIndex)!=Masks[i]) return 0;
    }
    HMODULE Engine=GetModuleHandleA("Engine.dll");
    BYTE* Code=Engine ? reinterpret_cast<BYTE*>(GetProcAddress(Engine,"?UpdateMovementAnimation@APawn@@QAEXM@Z")) : NULL;
    const BYTE Prefix[]={0x55,0x8B,0xEC,0x6A,0xFF,0x68};
    if(!Code || memcmp(Code,Prefix,sizeof(Prefix))) return 0;
    PresentationLocomotion=reinterpret_cast<FUpdateLocomotion>(Code);
    Checked=1;
    debugf("ModCoop: Verified buffered locomotion layout");
    return 1;
}

struct FPresentationLocomotionScope
{
    APawn* P;
    FVector Velocity,Acceleration;
    FRotator Rotation,DesiredRotation,RotationRate;
    BYTE Idle;
    UBOOL Walking,Crouched,PhysicsAnim;
    explicit FPresentationLocomotionScope(APawn* In):P(In),Velocity(In->Velocity),Acceleration(In->Acceleration),
        Rotation(In->Rotation),DesiredRotation(In->DesiredRotation),RotationRate(In->RotationRate),
        Idle(In->CurrentIdleState),Walking(In->bIsWalking),Crouched(In->bIsCrouched),PhysicsAnim(In->bPhysicsAnimUpdate) {}
    ~FPresentationLocomotionScope()
    {
        P->Velocity=Velocity; P->Acceleration=Acceleration; P->CurrentIdleState=Idle;
        P->Rotation=Rotation; P->DesiredRotation=DesiredRotation; P->RotationRate=RotationRate;
        P->bIsWalking=Walking; P->bIsCrouched=Crouched; P->bPhysicsAnimUpdate=PhysicsAnim;
    }
};

void UCoopNative::execUpdateProxyLocomotion(FFrame& Stack, void* Result)
{
    P_GET_OBJECT(APawn,P);
    P_GET_VECTOR(VisualVelocity);
    P_GET_BYTE(IdleState);
    P_GET_BYTE(MoveFlags);
    P_GET_FLOAT(DeltaTime);
    P_FINISH;
    *static_cast<UBOOL*>(Result)=0;
    if(!ValidPresentationPawn(P) || P->Health<=0 || P->bIncapacitated || P->Controller ||
       (P->Physics!=PHYS_Walking && P->Physics!=PHYS_Flying) || !VerifyPresentationLayout()) return;
    FPresentationLocomotionScope Saved(P);
    P->Velocity=VisualVelocity;
    // Native zero acceleration + zero velocity selects standing animation.
    P->Acceleration=VisualVelocity;
    // UpdateMovementAnimation also tries to turn toward DesiredRotation.
    // Facing is already buffered; prevent a second turn (and SetRotation's
    // attachment side effects) while selecting/blending movement animation.
    P->DesiredRotation=P->Rotation;
    P->RotationRate=FRotator(0,0,0);
    P->CurrentIdleState=IdleState;
    P->bIsWalking=(MoveFlags&1)!=0; P->bIsCrouched=(MoveFlags&2)!=0;
    P->bPhysicsAnimUpdate=1;
    PresentationLocomotion(P,0,Clamp(DeltaTime,0.f,0.1f));
    *static_cast<UBOOL*>(Result)=1;
}
