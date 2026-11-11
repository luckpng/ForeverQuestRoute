local A=TEST_ADDON
local C=A.Catalog
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS catalog: " .. name) end
local quests={
 [100]={name="Dungeon direta",zoneOrSort=1581,questLevel=20,requiredLevel=14,startedBy={{10}},preQuestGroup={90}},
 [101]={name="Item da dungeon",zoneOrSort=12,questLevel=19,requiredLevel=12,startedBy={{10}},objectives={[3]={{30,nil,4}}}},
 [102]={name="Quest da Horda",zoneOrSort=1581,questLevel=18,requiredRaces=2},
 [103]={name="Quest futura",zoneOrSort=1581,questLevel=28,requiredLevel=25},
 [104]={name="Quest do mapa",zoneOrSort=12,questLevel=20,requiredLevel=10,startedBy={{10}},objectives={[1]={{12,nil,8}}}},
 [105]={name="Alternativas",zoneOrSort=1581,questLevel=20,preQuestSingle={90,91}},
 [106]={name="Especial",zoneOrSort=1581,questLevel=20,requiredSkill={164,100}},
 [107]={name="Concluida",zoneOrSort=1581,questLevel=20},
 [108]={name="Requer ativa",zoneOrSort=1581,questLevel=20,preQuestGroup={-104}},
}
local npcs={
 [10]={name="Recrutador",spawns={[12]={{40,50}}}},
 [11]={name="Chefe da dungeon",spawns={[10029]={{30,40}}}},
 [12]={name="Lobo de fora",spawns={[12]={{70,70}}}},
}
local items={[30]={name="Emblema",npcDrops={11}}}
local function entity(records)
 local e={}
 setmetatable(e,{__index=function(_,key) return function(id) return records[id] and records[id][key] end end})
 return e
end
local timers={}
C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
local raw={private={dungeons={[1581]={"Deadmines",{10029},40,{{40,42,71}}}},
 areaIdToUiMapId="return {[12]=10,[40]=52}",areaIdToUiMapIdOverride="return {[40]=2542}"}}
LibQuestieDB={Quest=entity(quests),Npc=entity(npcs),Item=entity(items),Object=entity({}),
 RequireContract=function(v) return v==4 end,Support={Get=function() return raw end},
 Enum={raceMaskById={[1]=1,[95]=4294967296},classKeys={WARRIOR=1}}}
LibQuestieDB.Quest.GetAllIds=function() return {100,101,102,103,104,105,106,107,108} end
local guid="char-one"
UnitGUID=function() return guid end
UnitRace=function() return "Human","Human",1 end
UnitClass=function() return "Warrior","WARRIOR",1 end
C_QuestLog.GetAllCompletedQuestIDs=function() return {107} end
C_QuestLog.GetNumQuestLogEntries=function() return 0 end
C_QuestLog.IsQuestFlaggedCompleted=function(id) return id==107 end
C_QuestLog.IsComplete=function(id) return id==104 end
test("async indexing uses provider and dungeon aliases",function()
 C:Start()
 while #timers>0 do local fn=table.remove(timers,1); fn() end
 assert(C.ready and not C.loading and #C.records==9)
 assert(C.byID[100].dungeonID==1581 and C.byID[101].dungeonID==1581)
 assert(C.byID[104].dungeonID==nil)
end)
C:SyncCharacter()
test("remote dungeons show without visiting their map",function()
 local rows,counts=C:View(20,{tab="dungeons",status="all",myCharacter=true})
 assert(#rows==7 and counts.done==1)
 for _,row in ipairs(rows) do assert(row.quest.id~=102 and row.quest.id~=104) end
end)
test("completed and pending filters remain separate",function()
 local done=C:View(20,{tab="dungeons",status="done",myCharacter=true})
 local pending=C:View(20,{tab="dungeons",status="pending",myCharacter=true})
 assert(#done==1 and done[1].quest.id==107 and #pending==6)
end)
test("AND, OR, active prerequisites and special requirements",function()
 assert(C:State(C.byID[100],20)=="locked")
 assert(C:State(C.byID[105],20)=="locked")
 C.completed[91]=true; assert(C:State(C.byID[105],20)=="pending")
 C.completed[90]=true; assert(C:State(C.byID[100],20)=="pending")
 assert(C:State(C.byID[108],20)=="locked")
 C.logs[104]={questID=104}; assert(C:State(C.byID[108],20)=="pending")
 assert(C:State(C.byID[106],20)=="verify")
 assert(C:State(C.byID[104],20)=="turnin")
 C.logs[104]=nil
end)
test("race masks beyond 32 bits",function()
 assert(not C:MatchesCharacter(C.byID[102]))
 local original=UnitRace; UnitRace=function() return "Skyborne","Skyborne",95 end
 assert(C:MatchesCharacter({requiredRaces=4294967296}))
 assert(not C:MatchesCharacter({requiredRaces=1})); UnitRace=original
end)
test("minimum level blocks pending and does not mark as available",function()
 assert(C:State(C.byID[103],20)=="locked")
end)
test("quest giver and instance entrance use overridden map IDs",function()
 local text,point=C:Location(C.byID[100]); assert(text:find("Recrutador") and point.mapID==10 and point.x==.4)
 local entrance=C:Entrance(C.dungeons[1581]); assert(entrance.mapID==2542 and entrance.x==.42)
end)
test("history is isolated by character",function()
 C.character.completed[100]=true
 guid="char-two"; C:SyncCharacter(); assert(not C:Done(100))
 guid="char-one"; C:SyncCharacter(); assert(C:Done(100))
end)
test("unknown API completion stays unknown",function()
 local doneIDs,flag=C_QuestLog.GetAllCompletedQuestIDs,C_QuestLog.IsQuestFlaggedCompleted
 C_QuestLog.GetAllCompletedQuestIDs=nil; C_QuestLog.IsQuestFlaggedCompleted=nil; C:SyncCharacter()
 assert(C:State(C.byID[101],20)=="unknown")
 C_QuestLog.GetAllCompletedQuestIDs=doneIDs; C_QuestLog.IsQuestFlaggedCompleted=flag; C:SyncCharacter()
end)
test("global DB enriches recommendations with unaccepted local quests",function()
 local rows=C:Recommendations({mapID=10,level=20},{})
 assert(#rows==1 and rows[1].id==104 and rows[1].objectives[1].numRequired==8)
end)
test("search, dungeon selector and level filters",function()
 local rows=C:View(20,{tab="dungeons",status="all",search="101",dungeonID=1581,myCharacter=true})
 assert(#rows==1 and rows[1].quest.id==101)
 local all=C:View(20,{tab="dungeons",status="all",myCharacter=true,levelOnly=true})
 for _,row in ipairs(all) do assert(row.quest.id~=103) end
end)
test("all new tabs and selection render",function()
 A:Refresh(); assert(not A.lastError)
 A:SelectTab("dungeons"); assert(#A.entries>0 and A.rows[1].entry)
 A.view.status="done"; A:Render(); assert(#A.entries==2)
 A:SelectTab("history"); A.view.status="all"; A:Render(); assert(#A.entries==8)
 assert(A.detailTitle.text and A.sideRows[1].title.text)
end)
test("quest turned in records completion only for the active character",function()
 TEST_EVENTS.scripts.OnEvent(TEST_EVENTS,"QUEST_TURNED_IN",101)
 assert(C.character.completed[101])
 guid="char-two"; C:SyncCharacter(); assert(not C:Done(101))
 guid="char-one"; C:SyncCharacter(); assert(C:Done(101))
end)
test("missing prerequisite opens the catalog at its quest ID",function()
 quests[90]={name="Primeiro passo",questLevel=19,startedBy={{10}}}
 C:AddRecord(90); C.character.completed[100]=nil; C.completed[90]=nil
 A:ShowDetails({quest=C.byID[100],state="locked",reason="Pre-requisito"})
 A.selected={quest=C.byID[100]}
 A.previousButton.scripts.OnClick()
 assert(A.view.tab=="history" and A.view.status=="all" and A.view.search=="90")
 assert(#A.entries==1 and A.entries[1].quest.id==90)
end)
print("TOTAL " .. passed .. " catalog tests passed")
