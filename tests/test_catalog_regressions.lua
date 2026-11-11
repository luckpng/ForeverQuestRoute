local A=TEST_ADDON
local C=A.Catalog
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS catalog regression: " .. name) end

test("accented names and literal multiword searches",function()
 local q={id=321,title="A Vingança do Coração [Elite]"}
 assert(C:SearchMatches(q,"vinganca coracao"))
 assert(C:SearchMatches(q,"CORAÇÃO 321"))
 assert(C:SearchMatches(q,"[elite]"))
 assert(not C:SearchMatches(q,"vinganca missing"))
 assert(C:SearchMatches(q,"   "))
 q.title="Outro nome"; assert(not C:SearchMatches(q,"vinganca"))
end)

test("status filters distinguish available, blocked and turn-in quests",function()
 assert(C:MatchesStatus("pending","available",{}))
 assert(not C:MatchesStatus("locked","available",{}))
 assert(C:MatchesStatus("turnin","active",{}))
 assert(C:MatchesStatus("turnin","turnin",{}))
 assert(not C:MatchesStatus("active","turnin",{}))
 assert(C:MatchesStatus("verify","pending",{}))
 assert(C:MatchesStatus("locked","locked",{}))
end)

test("zero optional quest references do not invent prerequisite quest zero",function()
 local completed,logs,character=C.completed,C.logs,C.character
 C.completed={}; C.logs={}; C.character={completed={}}
 local q={id=567890,availableStartingWith=0,availableUntilCompleted=0,disabledByQuest=0}
 assert(C:State(q,20)=="pending")
 assert(not C:AreaExcluded(q,20))
 C.completed,C.logs,C.character=completed,logs,character
end)

test("loading transitions clear the previous character's history",function()
 local guid,flags=UnitGUID,C_QuestLog.IsQuestFlaggedCompleted
 local character,completed,logs=C.character,C.completed,C.logs
 C.character={completed={[999999]=true}}; C.completed={[999998]=true}; C.logs={[999997]={}}
 UnitGUID=function() return nil end; C_QuestLog.IsQuestFlaggedCompleted=nil
 C:SyncCharacter()
 assert(C.character==nil and C.completed==nil and next(C.logs)==nil)
 assert(C:Done(999999)==nil)
 UnitGUID=guid; C_QuestLog.IsQuestFlaggedCompleted=flags
 C.character,C.completed,C.logs=character,completed,logs
end)

test("older saved characters without a completed table are repaired",function()
 local saved=A.db.characters
 local character,completed,logs=C.character,C.completed,C.logs
 local guid=UnitGUID
 UnitGUID=function() return "Migration-Test" end
 for _,value in ipairs({42,"broken",{completed=42},{completed="broken"},{}}) do
    A.db.characters={["Migration-Test"]=value}
    C:SyncCharacter(); assert(type(C.character.completed)=="table")
    assert(not C:Done(987653))
 end
 A.db.characters=saved; UnitGUID=guid; C.character,C.completed,C.logs=character,completed,logs
end)

test("navigation scans past the first three remote givers",function()
 local provider,maps=C.provider,C.areaMaps
 local spawns={[1]={[1]={{20,30}}},[2]={[1]={{30,40}}},[3]={[1]={{40,50}}},[4]={[2]={{70,80}}}}
 C.provider={Npc={name=function(id) return "Giver " .. id end,spawns=function(id) return spawns[id] end}}
 C.areaMaps={[1]=101,[2]=202}
 local description,point=C:Location({id=900,title="Travel",startedBy={{1,2,3,4}}},false,202)
 assert(point and point.mapID==202 and point.x==.7 and point.y==.8)
 local lines=0; for _ in description:gmatch("[^\n]+") do lines=lines+1 end; assert(lines<=3)
 C.provider,C.areaMaps=provider,maps
end)

test("invalid provider coordinates never become navigation pins",function()
 local provider,maps=C.provider,C.areaMaps
 C.provider={Npc={spawns=function() return {[1]={{150,20},{20,-1},{25,35}}} end}}
 C.areaMaps={[1]=101}
 local _,point=C:Location({id=900,title="Travel",startedBy={{1}}},false,101)
 assert(point and point.x==.25 and point.y==.35)
 assert(C:Entrance({name="Broken",entrance={{1,200,20}}})==nil)
 assert(C:Entrance({name="Broken",entrance={{1,"20",20}}})==nil)
 C.provider,C.areaMaps=provider,maps
end)

test("disabled quests leave area totals unless already accepted or completed",function()
 local completed,logs,character=C.completed,C.logs,C.character
 C.completed={[44]=true}; C.logs={}; C.character={completed={}}
 local q={id=45,disabledByQuest=44}
 assert(C:AreaExcluded(q,20))
 C.logs[45]={questID=45}; assert(not C:AreaExcluded(q,20))
 C.logs[45]=nil; C.completed[45]=true; assert(not C:AreaExcluded(q,20))
 C.completed,C.logs,C.character=completed,logs,character
end)

test("area favorite filters leave completion totals intact",function()
 local records,tracker=C.records,A.Tracker
 local completed,logs,character=C.completed,C.logs,C.character
 C.records={{id=701,title="First",zone=12,level=20,startedBy={}},
    {id=702,title="Second",zone=12,level=20,startedBy={}}}
 C.completed={[701]=true}; C.logs={}; C.character={completed={}}
 A.Tracker={IsFavorite=function(_,id) return id==702 end}
 local rows,stats=C:AreaView({mapID=C:MapForArea(12),level=20},{status="all",favoritesOnly=true})
 assert(stats.total==2 and stats.done==1 and #rows==1 and rows[1].quest.id==702)
 C.records=records; A.Tracker=tracker; C.completed,C.logs,C.character=completed,logs,character
end)

test("view caches reduce API calls and expire before the next calculation",function()
 local race,class,flag=UnitRace,UnitClass,C_QuestLog.IsQuestFlaggedCompleted
 local completed,character=C.completed,C.character
 local races,classes,flags,done=0,0,0,false
 UnitRace=function() races=races+1; return "Human","Human",1 end
 UnitClass=function() classes=classes+1; return "Warrior","WARRIOR",1 end
 C_QuestLog.IsQuestFlaggedCompleted=function() flags=flags+1; return done end
 C.completed=nil; C.character=nil
 C:BeginView()
 for i=1,100 do C:MatchesCharacter({requiredRaces=1}); assert(C:Done(987654)==false) end
 assert(races==1 and classes==1 and flags==1)
 C:EndView(); done=true
 C:BeginView(); assert(C:Done(987654)==true); C:EndView()
 assert(races==2 and classes==2 and flags==2 and C.viewCache==nil)
 UnitRace=race; UnitClass=class; C_QuestLog.IsQuestFlaggedCompleted=flag
 C.completed,C.character=completed,character
end)

print("TOTAL " .. passed .. " catalog regression tests passed")
