// Build 139's skeletal MeshToWorld ignores PrePivot when bAlignBottom is set.
// Express that same cylinder-bottom alignment as a visual offset so the
// timestamped position actually reaches the mesh. Physics/collision stay put.
class CoopMeshSnapshotTrack extends CoopSnapshotTrack transient;

var bool bAlignmentSaved, bSavedAlignBottom;

simulated function vector AlignmentOffset()
{
    local vector X,Y,Z;
    if(!bSavedAlignBottom) return BasePrePivot;
    GetAxes(P.Rotation,X,Y,Z);
    // Verified MeshToWorld build-139 constant, added to CollisionHeight before
    // displacement along the actor's rotated Z axis. Original PrePivot is
    // deliberately ignored by that native alignment branch as well.
    return -Z*(P.CollisionHeight+5.85);
}

simulated function ApplyVisualPosition()
{
    if(P==None || P.bDeleteMe) return;
    if(!bAlignmentSaved)
    {
        bSavedAlignBottom=P.bAlignBottom;
        bAlignmentSaved=true;
    }
    if(bSavedAlignBottom) P.bAlignBottom=false;
    P.PrePivot=AlignmentOffset()+RenderPosition-P.Location;
}

simulated function Restore()
{
    if(P!=None && !P.bDeleteMe && bAlignmentSaved)
        P.bAlignBottom=bSavedAlignBottom;
    Super.Restore();
}
