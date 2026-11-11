local A=TEST_ADDON
local C=A.Catalog
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS area: " .. name) end
local function q(id,extra)
 local row={id=id,title="Area quest " .. id,zone=12,level=20,requiredLevel=10,
    startedBy={},finishedBy={},rawObjectives={}}
 for key,value in pairs(extra or {}) do row[key]=value end
 return row
end
C.records={q(200),q(201),q(202),q(203,{level=40,requiredLevel=40}),q(204),
 q(205,{zone=-81,startedBy={{10}}}),q(206,{specialFlags=1}),q(207,{dungeonID=1581}),
 q(208,{requiredRaces=2}),q(209,{zone=40,startedBy={{10}}}),q(210,{exclusiveTo={200}}),
 q(211,{requiredSkill={164,100}}),q(212,{requiredMaxLevel=10}),q(213,{specialFlags=1})}
C.byID={}; for _,row in ipairs(C.records) do C.byID[row.id]=row end
C.completed={[200]=true,[213]=true}; C.character.completed={}
C.logs={[201]={questID=201},[202]={questID=202}}
C_QuestLog.IsComplete=function(id) return id==202 end
local context={mapID=10,level=20,name="Zona teste"}
local filters={tab="area",status="all",search=""}
test("area totals include past and future quests but exclude other characters and maps",function()
 local rows,s=C:AreaView(context,filters)
 assert(#rows==7 and s.total==7 and s.done==1 and s.remaining==6 and s.percent==14)
 assert(s.active==1 and s.turnin==1 and s.locked==1 and s.pending==2 and s.verify==1)
 assert(s.excluded==2 and s.repeatables==2 and s.dungeons==1)
end)
test("geographic category wins over an out-of-zone quest giver",function()
 assert(not C:InMap(C.byID[209],10) and C:InMap(C.byID[209],2542))
 assert(C:InMap(C.byID[205],10))
end)
test("search and completed filter never shrink the area denominator",function()
 filters.search="200"; filters.status="done"
 local rows,s=C:AreaView(context,filters)
 assert(#rows==1 and rows[1].quest.id==200 and s.total==7 and s.remaining==6)
 filters.search="no results"
 rows,s=C:AreaView(context,filters); assert(#rows==0 and s.total==7)
 filters.search=""; filters.status="all"
end)
test("remaining includes accepted and ready-to-turn-in quests",function()
 filters.status="pending"
 local rows,s=C:AreaView(context,filters)
 assert(#rows==6 and s.remaining==6 and rows[1].quest.id==202 and rows[2].quest.id==201)
 filters.status="all"
end)
test("repeatables and dungeon inclusion are explicit",function()
 filters.areaDungeons=true
 local _,s=C:AreaView(context,filters); assert(s.total==8 and s.dungeons==0)
 filters.areaRepeatables=true
 _,s=C:AreaView(context,filters); assert(s.total==10 and s.done==2 and s.repeatables==0)
 filters.areaDungeons=false; filters.areaRepeatables=false
end)
test("turn-in updates progress even before server snapshot catches up",function()
 C.logs[201]=nil; C.character.completed[201]=true
 local _,s=C:AreaView(context,filters); assert(s.done==2 and s.remaining==5)
 C.logs[201]={questID=201}; C.character.completed[201]=nil
end)
test("unknown completion is visible and never counted as completed",function()
 local snapshot=C.completed; local api=C_QuestLog.IsQuestFlaggedCompleted
 C.completed=nil; C_QuestLog.IsQuestFlaggedCompleted=nil
 local _,s=C:AreaView(context,filters)
 assert(s.done==0 and s.unknown>0 and s.remaining==s.total)
 C.completed=snapshot; C_QuestLog.IsQuestFlaggedCompleted=api
end)
test("area switch and unavailable map do not retain previous totals",function()
 local _,s=C:AreaView({mapID=2542,level=20},filters); assert(s.total==1 and s.done==0)
 _,s=C:AreaView({level=20},filters); assert(s.total==0 and s.percent==0)
end)
test("area UI displays full progress and separate counts",function()
 A.context=context; A.view.search=""; A.view.status="all"; A:SelectTab("area")
 assert(A.areaStats.total==7 and A.summary.text:find("Faltam 6",1,true))
 assert(A.sideInfo.text:find("1 prontas para entregar",1,true))
 assert(A.tabs.area and A.areaDungeonCheck.shown and not A.levelCheck.shown)
end)
test("area command opens the area tab",function()
 A:Command("area"); assert(A.view.tab=="area" and A.frame.shown and not A.lastError)
end)
print("TOTAL " .. passed .. " area tests passed")
