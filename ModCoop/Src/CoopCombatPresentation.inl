// Build-139 skeletal channels. Kept separate from the incomplete SDK structs.
// All pointers here are local mesh data; only names and scalar state go on wire.
struct FCombatLayer
{
    FName Sequence,Bone;
    FLOAT Phase,Speed,EndPhase;
    BYTE Channel,Weight,Flags,Reserved;
};
struct FCombatPose { INT Count; FCombatLayer Layers[6]; };
struct FCombatPlay
{
    FName Sequence;
    BYTE Loop,Pad[3];
    FName Bone;
    INT Channel;
    FLOAT Weight,BlendSpeed,Rate,Phase;
};
struct FCombatChannel
{
    FCombatPlay Play;
    FLOAT Time,LastPhase,TweenRate,Tween,PreviousPhase,PreviousTween,Weight;
    INT BoneStart,BoneEnd;
    BYTE* Sequence;
};
// Resolved bone modifiers contain indices, matrices and scalar blend state,
// not UObject references. Preserve dismemberment and procedural bone changes.
struct FCombatModifier { BYTE Data[112]; };
static_assert(sizeof(FCombatLayer)==24 && sizeof(FCombatPose)==148,"combat wire layout");
static_assert(sizeof(FCombatPlay)==32 && sizeof(FCombatChannel)==72,"build-139 channel layout");
typedef UMeshInstance* (__fastcall* FCombatInstance)(UMesh*,DWORD,AActor*);
typedef bool (__fastcall* FCombatPlayFn)(UMeshInstance*,DWORD,const FCombatPlay&);
typedef void (__fastcall* FCombatRefresh)(UMeshInstance*,DWORD);
typedef void (__fastcall* FCombatSetActor)(UMeshInstance*,DWORD,AActor*);
static FCombatInstance CombatInstance=NULL;
static FCombatPlayFn CombatPlay=NULL;
static FCombatRefresh CombatRefresh=NULL;
static FCombatSetActor CombatSetActor=NULL;
static UClass* CombatMeshClass=NULL;

static UBOOL VerifyCombatLayout()
{
    static INT Checked=0;
    if(Checked) return Checked>0;
    Checked=-1;
    HMODULE E=GetModuleHandleA("Engine.dll");
    if(!E) return 0;
    UProperty* M=FindField<UProperty>(AActor::StaticClass(),TEXT("MeshInstance"));
    UProperty* Mesh=FindField<UProperty>(AActor::StaticClass(),TEXT("Mesh"));
    UProperty* Karma=FindField<UProperty>(AActor::StaticClass(),TEXT("KParams"));
    if(!M || M->Offset!=0xd4 || M->Offset!=offsetof(AActor,MeshInstance) ||
       !Mesh || Mesh->Offset!=offsetof(AActor,Mesh) || !Karma || Karma->Offset!=0x230 ||
       Karma->Offset!=offsetof(AActor,KParams)) return 0;
    UFunction* Read=FindField<UFunction>(UCoopNative::StaticClass(),TEXT("ReadCombatPose"));
    UStructProperty* Pose=Read ? FindField<UStructProperty>(Read,TEXT("Pose")) : NULL;
    UStructProperty* Layers=Pose ? FindField<UStructProperty>(Pose->Struct,TEXT("Layers")) : NULL;
    if(!Pose || !Layers || Pose->Struct->PropertiesSize!=sizeof(FCombatPose) ||
       Layers->Offset!=4 || Layers->ArrayDim!=6 || Layers->Struct->PropertiesSize!=sizeof(FCombatLayer)) return 0;
    const TCHAR* FieldNames[]={TEXT("Sequence"),TEXT("Bone"),TEXT("Phase"),TEXT("Speed"),TEXT("EndPhase"),TEXT("Channel"),TEXT("Weight"),TEXT("Flags"),TEXT("Reserved")};
    const INT FieldOffsets[]={0,4,8,12,16,20,21,22,23};
    for(INT i=0;i<ARRAY_COUNT(FieldNames);++i)
    {
        UProperty* Field=FindField<UProperty>(Layers->Struct,FieldNames[i]);
        if(!Field || Field->Offset!=FieldOffsets[i]) return 0;
    }
    BYTE* Channel=(BYTE*)GetProcAddress(E,"?GetChannel@USkeletalMeshInstance@@UAEPAUFAnimChannel@@ABUFPlayAnim@@@Z");
    BYTE* Seq=(BYTE*)GetProcAddress(E,"?GetSequence@ULodMeshInstance@@QAEPBUFMeshAnimSeq@@H@Z");
    const BYTE Signature[]={0x8b,0x44,0x24,0x04,0x8b,0x51,0x64,0x8d,0x04,0xc0};
    // Verify the exact channel reader (array +0x64, stride 72, seq pointer +0x44).
    if(!Channel || !Seq || memcmp(Seq,Signature,sizeof(Signature))) return 0;
    BYTE* Scale=(BYTE*)GetProcAddress(E,"?execSetBoneScale@AActor@@QAEXAAUFFrame@@PAX@Z");
    if(!Scale || Scale[0x11d]!=0xe8) return 0;
    BYTE* Modify=Scale+0x122+*(INT*)(Scale+0x11e);
    const BYTE ModifierArray[]={0x8b,0x93,0xf4,0,0,0};
    const BYTE ModifierStride[]={0x83,0xc7,0x70};
    if(memcmp(Modify+0xcc,ModifierArray,sizeof(ModifierArray)) || memcmp(Modify+0xfc,ModifierStride,sizeof(ModifierStride))) return 0;
    CombatInstance=(FCombatInstance)GetProcAddress(E,"?MeshGetInstance@UMesh@@UAEPAVUMeshInstance@@PBVAActor@@@Z");
    CombatPlay=(FCombatPlayFn)GetProcAddress(E,"?PlayAnim@ULodMeshInstance@@UAE_NABUFPlayAnim@@@Z");
    CombatRefresh=(FCombatRefresh)GetProcAddress(E,"?ForceBoneRefresh@USkeletalMeshInstance@@UAEXXZ");
    CombatSetActor=(FCombatSetActor)GetProcAddress(E,"?SetActor@ULodMeshInstance@@UAEXPAVAActor@@@Z");
    const BYTE BindSignature[]={0x8b,0x44,0x24,0x04,0x89,0x41,0x58,0xc2,0x04,0x00};
    BYTE* Destroy=(BYTE*)GetProcAddress(E,"?Destroy@USkeletalMeshInstance@@UAEXXZ");
    if(!CombatSetActor || memcmp((void*)CombatSetActor,BindSignature,sizeof(BindSignature)) ||
       !Destroy || Destroy[0x2b]!=0xe8) return 0;
    BYTE* Term=Destroy+0x30+*(INT*)(Destroy+0x2c);
    const BYTE BodyCount[]={0x8b,0x8e,0x74,0x01,0,0};
    const BYTE ModelCount[]={0x85,0x86,0x6c,0x01,0,0};
    if(memcmp(Term+0x42,BodyCount,sizeof(BodyCount)) || memcmp(Term+0x51,ModelCount,sizeof(ModelCount))) return 0;
    CombatMeshClass=FindObject<UClass>(NULL,TEXT("Engine.SkeletalMeshInstance"));
    if(!CombatInstance || !CombatPlay || !CombatRefresh || !CombatMeshClass) return 0;
    Checked=1;
    debugf("ModCoop: Verified isolated combat presentation layout");
    return 1;
}
static TArray<FCombatChannel>& CombatChannels(UMeshInstance* I)
{
    return *reinterpret_cast<TArray<FCombatChannel>*>(reinterpret_cast<BYTE*>(I)+0x64);
}
static TArray<FCombatModifier>& CombatModifiers(UMeshInstance* I)
{
    return *reinterpret_cast<TArray<FCombatModifier>*>(reinterpret_cast<BYTE*>(I)+0xf0);
}
static UBOOL ValidCombatInstance(UMeshInstance* I,APawn* P)
{
    return I && I->IsA(CombatMeshClass) && *(UMesh**)((BYTE*)I+0x54)==P->Mesh &&
        CombatChannels(I).Num()>=0 && CombatChannels(I).Num()<=32 &&
        CombatModifiers(I).Num()>=0 && CombatModifiers(I).Num()<=512;
}
static UBOOL CombatHasNoPhysics(UMeshInstance* I)
{
    return !(*(DWORD*)((BYTE*)I+0x16c)&0x1fffffff) &&
           !(*(DWORD*)((BYTE*)I+0x174)&0x1fffffff);
}
struct FVisualMeshCreationScope
{
    APawn* P;
    UMeshInstance* Mesh;
    UKarmaParamsCollision* Karma;
    explicit FVisualMeshCreationScope(APawn* In):P(In),Mesh(In->MeshInstance),Karma(In->KParams)
    { P->MeshInstance=NULL; P->KParams=NULL; }
    ~FVisualMeshCreationScope() { P->MeshInstance=Mesh; P->KParams=Karma; }
};
void UCoopNative::execReadCombatPose(FFrame& Stack,void* Result)
{
    P_GET_OBJECT(APawn,P);
    P_GET_STRUCT_REF(FCombatPose,Pose);
    P_FINISH;
    appMemzero(Pose,sizeof(*Pose));
    *static_cast<UBOOL*>(Result)=0;
    if(!P || P->bDeleteMe || !P->Mesh || !VerifyCombatLayout() || !ValidCombatInstance(P->MeshInstance,P)) return;
    TArray<FCombatChannel>& Channels=CombatChannels(P->MeshInstance);
    for(INT i=0;i<Channels.Num();++i)
    {
        FCombatChannel& C=Channels[i];
        if(C.Play.Sequence==NAME_None || !C.Sequence) continue;
        if(Pose->Count>=6 || C.Play.Channel<0 || C.Play.Channel>127 ||
           !(C.Play.Phase>=0 && C.Play.Phase<=1.01f) || !(C.Weight>=0 && C.Weight<=1.01f))
        { Pose->Count=0; return; }
        INT Frames=*(INT*)(C.Sequence+0x10);
        FLOAT FPS=*(FLOAT*)(C.Sequence+0x14);
        if(Frames<=0 || Frames>100000 || !(FPS>=0 && FPS<=1000)) { Pose->Count=0; return; }
        FCombatLayer& L=Pose->Layers[Pose->Count++];
        L.Sequence=C.Play.Sequence; L.Bone=C.Play.Bone; L.Channel=(BYTE)C.Play.Channel;
        L.Phase=Clamp(C.Play.Phase,0.f,1.f);
        L.Speed=Clamp(C.Play.Rate*FPS/Frames,0.f,32.f);
        L.EndPhase=1.f-1.f/Frames;
        L.Weight=(BYTE)Clamp<INT>(appRound((i==0 ? 1.f : C.Weight)*255),0,255);
        L.Flags=C.Play.Loop ? 1 : 0;
    }
    *static_cast<UBOOL*>(Result)=Pose->Count>0;
}

void UCoopNative::execBeginCombatPose(FFrame& Stack,void* Result)
{
    P_GET_OBJECT(APawn,P);
    P_GET_OBJECT(UMeshInstance,Visual);
    P_GET_STRUCT(FCombatPose,Pose);
    P_GET_FLOAT(DeltaTime);
    P_FINISH;
    *static_cast<UMeshInstance**>(Result)=NULL;
    if(!ValidPresentationPawn(P) || P->Controller || P->Health<=0 || P->bIncapacitated ||
       P->Physics==PHYS_Karma || P->Physics==PHYS_KarmaRagDoll ||
       !P->Mesh || !VerifyCombatLayout() || !ValidCombatInstance(P->MeshInstance,P) ||
       Pose.Count<=0 || Pose.Count>6) return;
    for(INT i=0;i<Pose.Count;++i)
        if(Pose.Layers[i].Sequence==NAME_None || !(Pose.Layers[i].Phase>=0 && Pose.Layers[i].Phase<=1) ||
           !(Pose.Layers[i].Speed>=0 && Pose.Layers[i].Speed<=32) || Pose.Layers[i].Channel>127) return;
    UMeshInstance* Original=P->MeshInstance;
    if(Visual && !ValidCombatInstance(Visual,P)) return;
    if(!Visual)
    {
        // MeshGetInstance calls SetMesh, which otherwise allocates a SECOND
        // ragdoll using the actor's KParams. It is not the actor's gameplay
        // mesh, so level teardown never releases those bodies in time.
        // Suppress physics only for this synchronous visual construction.
        { FVisualMeshCreationScope Scope(P); Visual=CombatInstance(P->Mesh,0,P); }
        if(!ValidCombatInstance(Visual,P)) return;
        // The script track owns a GC-visible reference; do not retain a level
        // through the editor's Standalone flag when the track is released.
        Visual->ClearFlags(RF_Standalone);
    }
    if(!CombatHasNoPhysics(Visual)) return;
    CombatSetActor(Visual,0,P);
    P->MeshInstance=Visual;
    CombatModifiers(Visual)=CombatModifiers(Original);
    TArray<FCombatChannel>& Channels=CombatChannels(Visual);
    // Remove expired layers so stale hit/fire overlays cannot remain active.
    for(INT i=Channels.Num()-1;i>=0;--i)
    {
        UBOOL Found=0;
        for(INT j=0;j<Pose.Count;++j)
            if(Channels[i].Play.Bone==Pose.Layers[j].Bone && Channels[i].Play.Channel==Pose.Layers[j].Channel) Found=1;
        if(!Found) Channels.Remove(i);
    }
    FAnimRep SavedSim[6]; appMemcpy(SavedSim,P->SimAnim,sizeof(SavedSim));
    UBOOL Good=1;
    for(INT i=0;i<Pose.Count;++i)
    {
        FCombatLayer& L=Pose.Layers[i];
        UBOOL NewSequence=1;
        for(INT j=0;j<Channels.Num();++j)
            if(Channels[j].Play.Bone==L.Bone && Channels[j].Play.Channel==L.Channel && Channels[j].Play.Sequence==L.Sequence) NewSequence=0;
        FCombatPlay Play; appMemzero(&Play,sizeof(Play));
        Play.Sequence=L.Sequence; Play.Bone=L.Bone; Play.Channel=L.Channel;
        Play.Loop=(L.Flags&1)!=0; Play.Weight=L.Weight/255.f; Play.Rate=1;
        // Let the native visual instance retain a short transition from its
        // previous pose. It never ticks: no AnimEnd/notifies can be dispatched.
        Play.Phase=NewSequence ? -1.f : L.Phase;
        if(!CombatPlay(Visual,0,Play)) { Good=0; break; }
        for(INT j=0;j<Channels.Num();++j)
        {
            FCombatChannel& C=Channels[j];
            if(C.Play.Bone!=L.Bone || C.Play.Channel!=L.Channel) continue;
            C.Play.Phase=L.Phase; C.PreviousPhase=L.Phase;
            C.Weight=Play.Weight; C.Play.Weight=Play.Weight;
            C.Tween=Min(1.f,C.Tween+Clamp(DeltaTime,0.f,0.1f)*Max(C.TweenRate,10.f));
            C.PreviousTween=C.Tween;
            break;
        }
    }
    appMemcpy(P->SimAnim,SavedSim,sizeof(SavedSim));
    if(!Good) { P->MeshInstance=Original; CombatSetActor(Visual,0,NULL); return; }
    CombatRefresh(Visual,0);
    *static_cast<UMeshInstance**>(Result)=Visual;
}

void UCoopNative::execEndCombatPose(FFrame& Stack,void* Result)
{
    P_GET_OBJECT(APawn,P);
    P_GET_OBJECT(UMeshInstance,Original);
    P_GET_OBJECT(UMeshInstance,Visual);
    P_FINISH;
    *static_cast<UBOOL*>(Result)=0;
    if(!VerifyCombatLayout() || !Visual || !Visual->IsA(CombatMeshClass)) return;
    if(P && P->MeshInstance==Visual) P->MeshInstance=Original;
    // A render-only instance must not retain a raw actor pointer after Draw,
    // especially when actor and mesh destruction order changes during travel.
    CombatSetActor(Visual,0,NULL);
    *static_cast<UBOOL*>(Result)=CombatHasNoPhysics(Visual) && (!P || P->MeshInstance!=Visual);
}

// ULevel.Tick calls this virtual after both actor tick passes, immediately
// before TickFlush. Works on listen and dedicated hosts without a viewport.
typedef void (__fastcall* FCombatNetTick)(ULevel*,DWORD,FLOAT);
static FCombatNetTick OriginalCombatNetTick=NULL;
static void __fastcall CombatNetTick(ULevel* L,DWORD Edx,FLOAT DT)
{
    ALevelInfo* Info=L ? L->GetLevelInfo() : NULL;
    if(Info && Info->NetMode!=NM_Client && Info->Game && !Info->Game->bDeleteMe)
    {
        UFunction* F=Info->Game->FindFunction(FName("CaptureCompletedFrame",FNAME_Find));
        if(F) Info->Game->ProcessEvent(F,NULL);
    }
    OriginalCombatNetTick(L,Edx,DT);
}
static void InstallCombatNetTick()
{
    if(OriginalCombatNetTick) return;
    HMODULE E=GetModuleHandleA("Engine.dll");
    void** V=E ? (void**)GetProcAddress(E,"??_7ULevel@@6BUObject@@@") : NULL;
    void* F=E ? GetProcAddress(E,"?TickNetServer@ULevel@@UAEXM@Z") : NULL;
    if(!V || !F || V[0x88/4]!=F) { debugf(NAME_Warning,"ModCoop: Post-simulation capture hook unavailable"); return; }
    OriginalCombatNetTick=PatchVTable(&V,0x88/4,CombatNetTick);
    debugf("ModCoop: Installed post-simulation capture before network replication");
}
void UCoopNative::execHasCompletedFrameCapture(FFrame& Stack,void* Result)
{
    P_FINISH;
    *static_cast<UBOOL*>(Result)=OriginalCombatNetTick!=NULL;
}



void UCoopNative::execCombatName(FFrame& Stack,void* Result)
{
    P_GET_STR(Text);
    P_FINISH;
    *static_cast<FName*>(Result)=Text.Len()<=128 ? FName(*Text) : FName(NAME_None);
}

void UCoopNative::execCanSendCombatFrame(FFrame& Stack,void* Result)
{
    P_GET_OBJECT(APlayerController,PC);
    P_FINISH;
    *static_cast<UBOOL*>(Result)=0;
    if(!PC || !PC->Player || PC->Player->IsA(UViewport::StaticClass()) ||
       !PC->Level || PC->Level->NetMode==NM_Client) return;
    typedef INT (__fastcall* FReady)(UNetConnection*,DWORD,UBOOL);
    static FReady Ready=(FReady)GetProcAddress(GetModuleHandleA("Engine.dll"),"?IsNetReady@UNetConnection@@UAEHH@Z");
    // Read-only budget query: never reset credit or force a network flush.
    if(Ready) *static_cast<UBOOL*>(Result)=Ready((UNetConnection*)PC->Player,0,0)!=0;
}

void UCoopNative::execSetCoopConnectionRate(FFrame& Stack,void* Result)
{
    P_GET_OBJECT(APlayerController,PC);
    P_GET_INT(Rate);
    P_FINISH;
    *static_cast<UBOOL*>(Result)=0;
    if(!PC || !PC->Level || PC->Level->NetMode==NM_Client || !PC->Player ||
       PC->Player->IsA(UViewport::StaticClass()) || PC->Player->Actor!=PC || Rate<5000 || Rate>1000000) return;
    INT Before=GetIntProperty(PC->Player,"CurrentNetSpeed");
    if(Before<0) return;
    if(Before!=Rate)
    {
        SetIntProperty(PC->Player,"CurrentNetSpeed",Rate);
        debugf("CoopConnectionRate: %s %i -> %i bytes/sec",PC->GetName(),Before,Rate);
    }
    *static_cast<UBOOL*>(Result)=GetIntProperty(PC->Player,"CurrentNetSpeed")==Rate;
}
