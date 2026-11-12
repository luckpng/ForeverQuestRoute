local A, passes = TEST_ADDON, 0
local T, E = A.Tracker, A.Engine
local saved = {db=A.db, log=C_QuestLog, map=C_Map, guid=UnitGUID, combat=InCombatLockdown, enum=Enum}
local function test(name, fn)
    fn(); passes=passes+1; print("PASS tracker: " .. name)
end
local guid, combat = "Character-One", false
UnitGUID=function() return guid end
InCombatLockdown=function() return combat end
A.db={options={}, quests={}}
local watched, rows, objectives = {}, {}, {}
C_Map={GetMapInfo=function(map) return {name="Map " .. map} end}
C_QuestLog={
    GetNumQuestLogEntries=function() return #rows end,
    GetInfo=function(i) return rows[i] end,
    GetQuestObjectives=function(id) return objectives[id] end,
    IsComplete=function(id) return id==3 end,
    GetNextWaypoint=function(id) return id==2 and 20 or 10, .4, .6 end,
    GetQuestWatchType=function(id) return watched[id] end,
    AddQuestWatch=function(id,...) assert(select("#",...)==0); watched[id]=1; return true end,
    RemoveQuestWatch=function(id) watched[id]=nil; return true end,
}
rows={{isHeader=true}, {questID=1,title="Nearby"}, {questID=2,title="Other map"},
    {questID=3,title="Delivery"}, {questID=4,title="Hidden",isHidden=true}, {questID=1,title="Duplicate"}}
objectives[1]={{text="Collect 3/10",type="item",numRequired=10,numFulfilled=3},
    {text="Visit camp",finished=true}}
objectives[2]={{text="Kill 2/4",numRequired=4,numFulfilled=2}}

test("journal keeps other maps, skips headers, hidden and duplicate entries", function()
    local entries=T:Snapshot({mapID=10}); local ids={}
    for _,entry in ipairs(entries) do ids[entry.quest.id]=entry end
    assert(#entries==3 and ids[1] and ids[2] and ids[3] and not ids[4])
    assert(ids[2].point.mapID==20 and ids[3].state=="turnin")
end)
test("objectives combine counts and boolean completion without mutating source", function()
    local normalized,progress=T:Objectives(1)
    assert(progress.required==11 and progress.fulfilled==4 and progress.completed==1 and progress.total==2)
    assert(progress.percent==36 and normalized[2].finished)
    assert(objectives[1][2].numRequired==nil)
end)
test("missing objectives remain explicitly unknown", function()
    local normalized,progress=T:Objectives(99)
    assert(#normalized==0 and not progress.known and progress.text=="Objetivos indisponiveis")
end)
test("invalid counts and overcomplete objectives stay bounded", function()
    objectives[9]={{text="bad",numRequired=0/0,numFulfilled=math.huge},
        {text="full",numRequired=2,numFulfilled=20}}
    local normalized,progress=T:Objectives(9)
    assert(progress.percent>=0 and progress.percent<=100)
    assert(normalized[2].numFulfilled==2 and normalized[1].numFulfilled==0)
end)
test("favorites and focus are isolated by character", function()
    assert(T:ToggleFavorite(2)); assert(T:SetFocus(1))
    guid="Character-Two"
    assert(not T:IsFavorite(2) and T:GetFocus()==nil)
    assert(T:ToggleFavorite(3))
    guid="Character-One"
    assert(T:IsFavorite(2) and not T:IsFavorite(3) and T:GetFocus()==1)
end)
test("focus and favorites win deterministic journal order", function()
    local entries=T:Snapshot({mapID=10})
    assert(entries[1].quest.id==1 and entries[2].quest.id==2 and entries[3].quest.id==3)
    assert(T:SetFocus(nil)); assert(not T:ToggleFavorite(2))
    entries=T:Snapshot({mapID=10}); assert(entries[1].quest.id==3)
end)
test("native watch toggles honor the client signature and expose failure", function()
    Enum={QuestWatchType={Manual=7}}
    assert(T:SetTracked(1,true)); assert(T:IsTracked(1) and watched[1]==1)
    assert(T:SetTracked(1,false)); assert(not T:IsTracked(1))
    C_QuestLog.AddQuestWatch=function() return false end
    local ok,reason=T:SetTracked(1,true); assert(not ok and reason:find("recusou",1,true))
end)
test("combat and absent watch APIs produce actionable errors", function()
    combat=true; local ok,reason=T:SetTracked(1,true)
    assert(not ok and reason:find("combate",1,true)); combat=false
    C_QuestLog.AddQuestWatch=nil
    ok,reason=T:SetTracked(1,true); assert(not ok and reason:find("indisponivel",1,true))
end)
test("invalid quest IDs never enter persistent favorites or focus", function()
    assert(not T:ToggleFavorite(-1) and not T:ToggleFavorite("2") and not T:ToggleFavorite(1.5))
    assert(not T:SetFocus(0) and not T:SetTracked(-1,true))
end)
test("missing GUID does not mix anonymous character settings", function()
    guid=nil; assert(T:Store()==nil and not T:ToggleFavorite(1) and not T:SetFocus(1))
    guid="Character-One"
end)
test("route prioritizes accepted and chosen quests without bypassing filters", function()
    local quests={
        {id=1,mapID=10,level=20,x=.4,y=.4},
        {id=2,mapID=10,level=20,x=.4,y=.4,accepted=true},
        {id=3,mapID=10,level=20,x=.4,y=.4,favorite=true},
        {id=4,mapID=10,level=20,x=.4,y=.4,focused=true},
        {id=5,mapID=20,level=20,x=.4,y=.4,focused=true},
        {id=6,mapID=10,level=20,x=.4,y=.4,favorite=true,ignored=true},
    }
    local route=E.Build(quests,{mapID=10,level=20,position={x=.4,y=.4}},nil)
    assert(#route==4 and route[1].id==4 and route[2].id==3 and route[3].id==2)
    assert(quests[1].score==nil)
end)
test("corrupt drop rates and route limits do not poison scoring", function()
    local q={id=1,mapID=10,level=20,x=.4,y=.4,playerLevel=20,dropRate=0,
        objectives={{type="item",numRequired=5,numFulfilled=0}}}
    local effort,reason=E.Effort(q,E.defaults)
    assert(effort<math.huge and reason:find("drop desconhecido",1,true))
    local route=E.Build({q},{mapID=10,level=20},{limit=0/0,maxAbove="bad"})
    assert(#route==1)
end)
test("corrupt saved tracker tables recover without mixing characters", function()
    A.db.characters="bad"; assert(type(T:Store().favorites)=="table")
    A.db.characters[guid]=true; assert(type(T:Store().favorites)=="table")
    A.db.characters[guid].tracker={favorites=false,focus=0/0}
    assert(type(T:Store().favorites)=="table" and T:GetFocus()==nil)
    A.db.characters[guid].tracker=false; assert(T:ToggleFavorite(2))
end)
test("invalid waypoint coordinates are never exposed as navigation targets", function()
    local previous=C_QuestLog.GetNextWaypoint
    C_QuestLog.GetNextWaypoint=function() return 10, 0/0, 2 end
    for _,entry in ipairs(T:Snapshot({})) do assert(entry.point==nil) end
    C_QuestLog.GetNextWaypoint=previous
end)
test("compact tracker paginates all quests and supports focus, destination and locking", function()
    local previousRows,previousContext=rows,A.context
    local previousRefresh,previousNavigate=A.Refresh,A.Navigate
    local visible=A.db.options.trackerVisible
    rows={}; for i=1,7 do rows[i]={questID=i,title="Quest " .. i} end
    A.context={mapID=10}; A.db.options.trackerVisible=true
    A:CreateTrackerUI(); A.trackerFrame:Show(); A.trackerPage=1; A:RenderTracker()
    assert(A.trackerPages==2 and A.trackerRows[4].entry and A.trackerPageText.text=="1 / 2")
    A.trackerNext.scripts.OnClick(); assert(A.trackerPage==2 and A.trackerRows[3].entry and not A.trackerRows[4].entry)
    A.trackerPrevious.scripts.OnClick(); assert(A.trackerPage==1)
    A.trackerNext.scripts.OnClick(); assert(A.trackerPage==2)
    local marked,refreshes
    A.Navigate=function(_,point) marked=point end
    A.Refresh=function() refreshes=true end
    local first=A.trackerRows[1].entry
    A.trackerRows[1].scripts.OnClick(A.trackerRows[1],"LeftButton")
    assert(T:GetFocus()==first.quest.id and marked.mapID==first.point.mapID and marked.x==first.point.x
        and marked.y==first.point.y and refreshes and A.trackerPage==1)
    local reveal,oldOpen=A.OpenJournalQuest,A.OpenJournalQuest
    A.OpenJournalQuest=function(_,id) reveal=id; return true end
    A.trackerRows[1].scripts.OnClick(A.trackerRows[1],"RightButton"); assert(reveal==first.quest.id)
    A.OpenJournalQuest=oldOpen
    A:SetTrackerLocked(true); assert(A.db.options.trackerLocked and A.trackerLock.text=="Destravar")
    A:SetTrackerLocked(false); assert(not A.db.options.trackerLocked)
    T:Store().position={"TOP","TOP",10,20}; A:ResetTrackerPosition(); assert(T:Store().position==nil)
    A:ToggleTracker(); assert(not A.db.options.trackerVisible and not A.trackerFrame:IsShown())
    A:ToggleTracker(); assert(A.db.options.trackerVisible and A.trackerFrame:IsShown())
    rows=previousRows; A.context=previousContext; A.Refresh=previousRefresh; A.Navigate=previousNavigate
    A.db.options.trackerVisible=visible; A.trackerFrame:Hide()
end)
test("compact position restores after late GUID and rejects out of bounds saves", function()
    local frame=A.trackerFrame
    local point,previousSetPoint,previousCharacter
    previousSetPoint,previousCharacter=frame.SetPoint,A.trackerCharacter
    frame.SetPoint=function(_,anchor,_,relative,x,y) point={anchor,relative,x,y} end
    local store=T:Store(); store.position={"TOPLEFT","TOPLEFT",120,-80}
    A.trackerCharacter=nil; guid=nil; A:RestoreTrackerPosition(); assert(point==nil)
    guid="Character-One"; A:RestoreTrackerPosition()
    assert(point[1]=="TOPLEFT" and point[3]==120 and A.trackerCharacter==guid)
    store.position={"TOPLEFT","TOPLEFT",1e200,0}; A:RestoreTrackerPosition()
    assert(point[1]=="RIGHT" and point[3]==-30 and store.position==nil)
    frame.SetPoint=previousSetPoint; A.trackerCharacter=previousCharacter
end)
test("compact scale adapts when display resolution changes", function()
    local parentWidth,parentHeight=UIParent.GetWidth,UIParent.GetHeight
    local previousScale=A.trackerFrame.SetScale
    local scale
    A.trackerFrame.SetScale=function(_,value) scale=value end
    UIParent.GetWidth=function() return 200 end; UIParent.GetHeight=function() return 300 end
    A:ApplyTrackerScale(); assert(scale>=.35 and scale<1)
    UIParent.GetWidth=function() return 2000 end; UIParent.GetHeight=function() return 1500 end
    A:ApplyTrackerScale(); assert(scale==1)
    A.trackerFrame.SetScale=previousScale; UIParent.GetWidth=parentWidth; UIParent.GetHeight=parentHeight
end)
test("temporarily hidden parent UI does not disable the compact tracker preference", function()
    local frame=A.trackerFrame
    A.db.options.trackerVisible=true; frame:Show()
    frame.scripts.OnHide(frame)
    assert(A.db.options.trackerVisible)
    frame:Hide(); frame.scripts.OnHide(frame)
    assert(not A.db.options.trackerVisible)
end)
test("missing global waypoint falls back to the map specific waypoint",function()
    local global,localMap=C_QuestLog.GetNextWaypoint,C_QuestLog.GetNextWaypointForMap
    C_QuestLog.GetNextWaypoint=function() end
    C_QuestLog.GetNextWaypointForMap=function(id,map) assert(id==1 and map==10); return .2,.3 end
    local destination=T:Destination(1,false,{mapID=10})
    assert(destination.mapID==10 and destination.x==.2 and destination.y==.3)
    C_QuestLog.GetNextWaypoint=global; C_QuestLog.GetNextWaypointForMap=localMap
end)

test("missing waypoints use only the matching visible quest map marker",function()
    local global,pois=C_QuestLog.GetNextWaypoint,C_QuestLog.GetQuestsOnMap
    C_QuestLog.GetNextWaypoint=function() end
    C_QuestLog.GetQuestsOnMap=function() return {{questID=2,x=.1,y=.1},{questID=1,x=.2,y=.2,isHidden=true},{questID=1,x=.6,y=.7}} end
    local destination=T:Destination(1,false,{mapID=10})
    assert(destination.x==.6 and destination.y==.7)
    C_QuestLog.GetNextWaypoint=global; C_QuestLog.GetQuestsOnMap=pois
end)

test("delivery without a native waypoint uses the known receiver",function()
    local global,location,record=C_QuestLog.GetNextWaypoint,A.Catalog.Location,A.Catalog.byID[3]
    C_QuestLog.GetNextWaypoint=function() end
    A.Catalog.byID[3]={id=3}
    A.Catalog.Location=function(_,q,finish,map) assert(q.id==3 and finish and map==10); return "Receiver",{mapID=10,x=.8,y=.9} end
    local destination=T:Destination(3,true,{mapID=10})
    assert(destination.x==.8 and destination.source:find("Entrega",1,true))
    C_QuestLog.GetNextWaypoint=global; A.Catalog.Location=location; A.Catalog.byID[3]=record
end)

test("Questie objective fallback skips finished objectives and chooses a nearby pending spawn",function()
    local C=A.Catalog; local provider,maps=C.provider,C.areaMaps
    C.areaMaps={[12]=10,[13]=20}
    C.provider={Npc={spawns=function(id)
        if id==100 then return {[12]={{40,40}}} end
        return {[12]={{80,80},{42,40}},[13]={{1,1}}}
    end}}
    local q={id=1,title="Pending objective",rawObjectives={{{100},{101}}}}
    local destination=C:ObjectiveLocation(q,{{type="monster",finished=true},{type="monster",finished=false}},
        {mapID=10,position={x=.4,y=.4}})
    assert(destination.mapID==10 and destination.x==.42 and destination.y==.4)
    assert(destination.source:find("aproximado",1,true))
    assert(not C:ObjectiveLocation(q,{{type="monster",finished=false}},{}))
    assert(not C:ObjectiveLocation(q,{{type="event",finished=false}},{}))
    C.provider=provider; C.areaMaps=maps
end)

test("item objective fallback uses the known drop source",function()
    local C=A.Catalog; local provider,maps=C.provider,C.areaMaps
    C.areaMaps={[12]=10}
    C.provider={Item={npcDrops=function() return {100} end},Npc={spawns=function() return {[12]={{30,40}}} end}}
    local destination=C:ObjectiveLocation({title="Item quest",rawObjectives={[3]={{900}}}},
        {{type="item",finished=false}},{mapID=10})
    assert(destination and destination.x==.3 and destination.y==.4)
    C.provider=provider; C.areaMaps=maps
end)

test("clicking a quest without any known location opens its details without chat spam",function()
    local global=C_QuestLog.GetNextWaypoint
    local open,refresh,printMessage,navigate=A.OpenJournalQuest,A.Refresh,A.Print,A.Navigate
    C_QuestLog.GetNextWaypoint=function() end
    local opened
    A.OpenJournalQuest=function(_,id) opened=id end
    A.Refresh=function() end
    A.Print=function() error("Unwanted chat warning") end
    A.Navigate=function() error("Unknown location must not navigate") end
    local row=A.trackerRows[1]; local entry=row.entry
    row.entry={quest={id=4444,title="Scripted quest",objectives={}}}
    row.scripts.OnClick(row,"LeftButton"); assert(opened==4444)
    opened=nil; row.scripts.OnClick(row,"LeftButton"); assert(opened==4444)
    row.entry=entry; C_QuestLog.GetNextWaypoint=global
    A.OpenJournalQuest=open; A.Refresh=refresh; A.Print=printMessage; A.Navigate=navigate
end)

A.db=saved.db; C_QuestLog=saved.log; C_Map=saved.map; UnitGUID=saved.guid
InCombatLockdown=saved.combat; Enum=saved.enum
print("TOTAL " .. passes .. " tracker tests passed")
