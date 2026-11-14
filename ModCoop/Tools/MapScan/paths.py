# paths
# Purpose: where the scans find the game's maps and the UnrealScript sources, relative to this file.
# Entry points: MAPS, CODE, campaign_maps().
# Logging: none yet.
# State: none yet.
# Known limitations: expects Code next to GameData.
import glob,os

CODE=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','..'))
MAPS=os.path.join(os.path.dirname(CODE),'GameData','Maps')

def campaign_maps():
    return [p for p in sorted(glob.glob(os.path.join(MAPS,'*.ctm'))) if os.path.basename(p)[:3] in('GEO','RAS','YYY','PRO','EPI')]
