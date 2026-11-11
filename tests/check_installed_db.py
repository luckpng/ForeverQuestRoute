"""Read-only catalog integration check against an installed QuestieDB baked TOC.

Uses the actual schema, raw metadata and zone support files. It does not emulate
Questie's runtime correction layers or server quest availability.
Usage: python tests/check_installed_db.py "CAMINHO/Interface/AddOns/QuestieDB"
Requires: lupa, cbor2.
"""
from pathlib import Path
import base64
import re
import sys
import zlib
from functools import lru_cache

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / ".tools"))
import cbor2
from lupa.lua51 import LuaRuntime

provider_path = Path(sys.argv[1])
metadata = {}
for line in (provider_path / "QuestieDB_Forever.toc").read_text(encoding="utf-8-sig").splitlines():
    if line.startswith("## "):
        key, sep, value = line[3:].partition(": ")
        if sep:
            metadata[key] = value


def stored(key):
    value = metadata.get(key)
    if value and re.fullmatch(r"~\d+~", value):
        return "".join(metadata[f"{key}-{i}"] for i in range(1, int(value[1:-1]) + 1))
    return value


lua = LuaRuntime(unpack_returned_tuples=True)
addon, provider = lua.table(), lua.table()
lua.globals().A = addon
lua.globals().LibQuestieDB = provider


def convert(value):
    if isinstance(value, bytes):
        return value.decode("utf-8")
    if isinstance(value, dict):
        return lua.table_from({convert(k): convert(v) for k, v in value.items() if v is not None})
    if isinstance(value, list):
        return lua.table_from({i: convert(v) for i, v in enumerate(value, 1) if v is not None})
    return value


schemas = {}
for entity in ("Quest", "Npc", "Item", "Object"):
    schema = lua.execute((provider_path / f"src/meta/{entity.lower()}Meta.lua").read_text(), "QuestieDB", provider)
    schemas[entity] = schema


@lru_cache(maxsize=None)
def scalar(entity, quest_id):
    value = stored(f"X-{entity}-{quest_id}-S")
    return cbor2.loads(base64.b64decode(value)) if value else {}


def read(entity, quest_id, field):
    schema = schemas[entity]
    index = schema["keys"][field]
    if not index:
        return None
    if schema["types"][index] == "table":
        value = stored(f"X-{entity}-{quest_id}-{index}")
        return convert(cbor2.loads(base64.b64decode(value))) if value else None
    return convert(scalar(entity, quest_id).get(index))


lua.globals().PY_READ = read
for entity in schemas:
    provider[entity] = lua.eval("function(kind) return setmetatable({}, {__index=function(_,field) return function(id) return PY_READ(kind,id,field) end end}) end")(entity)

ids = cbor2.loads(zlib.decompress(base64.b64decode(stored("X-Quest-IDS"))))
provider["Quest"]["GetAllIds"] = lua.eval("function(ids) return function() return ids end end")(convert(ids))
lua.execute('''
UnitRace=function() return "Human","Human",1 end
UnitClass=function() return "Warrior","WARRIOR",1 end
UnitGUID=function() return "Integration-Character" end
UnitLevel=function() return 22 end
UnitFactionGroup=function() return "Alliance" end
IsInInstance=function() return false end
InCombatLockdown=function() return false end
C_Map={GetAreaInfo=function() return nil end}
C_QuestLog={GetAllCompletedQuestIDs=function() return {166} end,
  GetNumQuestLogEntries=function() return 0 end}
local queue={}
C_Timer={After=function(_,fn) queue[#queue+1]=fn end}
function DRAIN() while #queue>0 do table.remove(queue,1)() end end
A.Schedule=function() end
A.db={options={maxBelow=7,maxAbove=2},quests={}}
ZONE={private={}}
QuestieLoader={ImportModule=function(_,name)
 if name=="ZoneDB" then return ZONE end
 return {Current=1,Classic=1,Tbc=2,Wotlk=3,Cata=4,MoP=5}
end}
LibQuestieDB.RequireContract=function() return true end
LibQuestieDB.Support={Get=function() return ZONE end}
LibQuestieDB.Enum={raceMaskById={[1]=1},classKeys={WARRIOR=1}}
''')
for file in ("dungeons.lua", "areaIdToUiMapId.lua"):
    lua.execute((provider_path / "support/Forever/Zones" / file).read_text(encoding="utf-8-sig"))
for file in ("Engine.lua", "Adapter.lua", "Catalog.lua", "Requirements.lua", "Area.lua"):
    lua.execute((root / "ForeverQuestRoute" / file).read_text(), "ForeverQuestRoute", addon)
lua.execute('''
A.Catalog:Start(); DRAIN(); A.Catalog:SyncCharacter()
assert(A.Catalog.ready, A.Catalog.message)
assert(#A.Catalog.records>4000)
assert(A.Catalog.byID[166].dungeonID==1581)
assert(A.Catalog.byID[214].dungeonID==1581)
local rows,counts=A.Catalog:View(22,{tab="dungeons",status="all",myCharacter=true})
assert(#rows>100 and counts.done==1)
local names={}
for _,row in ipairs(rows) do names[row.dungeon.id]=true end
local dungeons=0; for _ in pairs(names) do dungeons=dungeons+1 end
local done=A.Catalog:View(22,{tab="dungeons",status="done",myCharacter=true,dungeonID=1581})
assert(#done==1 and done[1].quest.id==166)
local giver,point=A.Catalog:Location(A.Catalog.byID[166])
assert(point and point.mapID>0 and point.x>0 and point.x<1)
local entrance=A.Catalog:Entrance(A.Catalog.dungeons[1581])
assert(entrance and entrance.mapID>0)
local catalog=A.Catalog:View(22,{tab="history",status="all",myCharacter=true})
local states={}
for _,entry in ipairs(catalog) do states[entry.state]=(states[entry.state] or 0)+1 end
assert((states.pending or 0)>100)
print("Installed DB: " .. #A.Catalog.records .. " raw quests; " .. #rows .. " character dungeon quests; " .. dungeons .. " dungeon groups")
print("PASS actual Deadmines IDs, character completion, remote list, giver/map and entrance")
for k,v in pairs(states) do print("  " .. k .. ": " .. v) end
-- Check the area of a sample quest using the actual Forever map mapping.
local mankrik=A.Catalog.byID[4921]
assert(mankrik and mankrik.zone==17)
local barrens=A.Catalog:MapForArea(17)
assert(barrens and A.Catalog:InMap(mankrik,barrens))
LibQuestieDB.Enum.raceMaskById[2]=2
UnitRace=function() return "Orc","Orc",2 end
A.Catalog.completed={[4921]=true}
local done,areaStats=A.Catalog:AreaView({mapID=barrens,level=22}, {status="done"})
assert(areaStats.total>30 and areaStats.done==1)
assert(#done==1 and done[1].quest.id==4921)
local missing,filteredStats=A.Catalog:AreaView({mapID=barrens,level=22},{status="pending",search="impossible search"})
assert(#missing==0 and filteredStats.total==areaStats.total and filteredStats.remaining==areaStats.total-1)
print("PASS actual Barrens map " .. barrens .. ": " .. areaStats.total .. " area quests; completed Mankrik counted; search leaves totals intact")
''')
