local A = TEST_ADDON
local E = A.Engine
local passes = 0
local function test(name, fn)
    fn()
    passes = passes + 1
    print("PASS " .. name)
end
local function options()
    local o = {}; for k,v in pairs(E.defaults) do o[k] = v end; return o
end
local function quest(id, extra)
    local q = {id=id, title="Quest " .. id, mapID=10, level=20, x=.4, y=.4, playerLevel=20,
        objectives={{type="monster",numRequired=8,numFulfilled=0}}}
    for k,v in pairs(extra or {}) do q[k] = v end
    return q
end
local context = {mapID=10,level=20,position={x=.4,y=.4},aspect=1}
test("filters map, level, ignored, finished and group", function()
    local r = E.Build({quest(1),quest(2,{mapID=11}),quest(3,{level=23}),
        quest(4,{level=12}),quest(5,{ignored=true}),quest(6,{group=true}),quest(7,{finished=true})},context,options())
    assert(#r==1 and r[1].id==1)
end)
test("range boundaries included", function()
    local r=E.Build({quest(1,{level=13}),quest(2,{level=22})},context,options())
    assert(#r==2)
end)
test("completed delivery bypasses difficulty filters", function()
    local r=E.Build({quest(1,{complete=true,group=true,level=30})},context,options())
    assert(#r==1)
end)
test("item objective penalty and preference", function()
    local q=quest(1,{objectives={{type="item",numRequired=8}}})
    local o=options(); local penalized=E.Effort(q,o); o.avoidItems=false
    assert(penalized>E.Effort(q,o))
    assert(penalized>E.Effort(quest(2),options()))
end)
test("lower known drops increase expected effort", function()
    local q=quest(1,{objectives={{type="item",numRequired=8}},dropRate=.1})
    local low=E.Effort(q,options()); q.dropRate=.8
    assert(low>E.Effort(q,options()))
end)
test("unknown drops are explicitly labeled", function()
    local _,why=E.Effort(quest(1,{objectives={{type="item",numRequired=8}}}),options())
    assert(why:find("drop desconhecido",1,true))
end)
test("progress reduces effort", function()
    local q=quest(1); local before=E.Effort(q,options())
    q.objectives[1].numFulfilled=7
    assert(E.Effort(q,options())<before)
end)
test("nearby objectives cluster and ties are deterministic", function()
    local r=E.Build({quest(3,{x=.42}),quest(2,{x=.41}),quest(1,{x=.41})},context,options())
    assert(r[1].id==1 and r[2].id==2 and r[3].id==3)
end)
test("missing coordinates and unknown levels remain visible", function()
    local r=E.Build({{id=1,mapID=10,objectives={}}},context,options())
    assert(#r==1 and r[1].reason:find("sem coordenadas",1,true))
end)
test("limit and inputs stay intact", function()
    local q=quest(1); local o=options(); o.limit=1
    local r=E.Build({q,quest(2)},context,o)
    assert(#r==1 and q.score==nil and q.effort==nil)
end)
test("map aspect ratio used", function()
    assert(E.Distance({x=0,y=0},{x=.5,y=0},2)==1)
end)

-- Model game API responses rather than deriving expectations from implementation.
C_Map = {
    GetBestMapForUnit=function() return 10 end,
    GetPlayerMapPosition=function() return {GetXY=function() return .2,.3 end} end,
    GetMapWorldSize=function() return 2000,1000 end,
    GetMapInfo=function() return {name="Zona de teste"} end,
}
UnitLevel=function() return 20 end
local requests=0
C_QuestLog={
    GetNumQuestLogEntries=function() return 3 end,
    GetInfo=function(i)
        return ({ {isHeader=true}, {questID=1,title="Aceita",level=20},
            {questID=2,title="Outro mapa",level=20} })[i]
    end,
    GetQuestsOnMap=function() return {{questID=1,x=.1,y=.1},{questID=4,x=.7,y=.7}} end,
    GetNextWaypoint=function(id) if id==1 then return 10,.6,.5 else return 11,.4,.4 end end,
    GetQuestDifficultyLevel=function() return 20 end,
    IsComplete=function() return false end,
    GetQuestObjectives=function() return {{type="monster",numRequired=5,numFulfilled=1}} end,
    GetQuestTagInfo=function() return nil end,
    IsQuestFlaggedCompleted=function() return false end,
    RequestLoadQuestByID=function() requests=requests+1 end,
}
C_QuestLine={GetAvailableQuestLines=function() return {
    {questID=1,x=.1,y=.1,questName="Duplicada"},
    {questID=3,x=.3,y=.4,questName="Disponivel",startMapID=10},
    {questID=5,x=.2,y=.2,questName="Oculta",isHidden=true},
    {questID=6,x=.2,y=.2,questName="Fora",startMapID=12},
} end}
A.db={options=options(),quests={[3]={dropRate=.25}}}
test("context gets both map dimensions",function()
    local ctx=A:Context(); assert(ctx.aspect==2 and ctx.position.y==.3 and ctx.level==20)
end)
test("collection deduplicates and uses next objective waypoint",function()
    local qs=A:Collect(A:Context()); local ids={}
    for _,q in ipairs(qs) do ids[q.id]=q end
    assert(#qs==3 and not ids[2] and not ids[5] and not ids[6])
    assert(ids[1].x==.6 and ids[1].accepted)
    assert(ids[3].dropRate==.25 and not ids[3].accepted)
end)
test("missing data requests do not loop",function()
    A:Collect(A:Context()); A:Collect(A:Context()); assert(requests==1)
end)
test("API exceptions are captured",function()
    assert(A:Call({Broken=function() error("api unavailable") end},"Broken")==nil)
    assert(A.apiWarnings.Broken:find("api unavailable",1,true))
end)
test("missing optional APIs are tolerated",function()
    C_QuestLine=nil; C_QuestLog.GetNextWaypoint=nil
    assert(#A:Collect(A:Context())==2)
end)

-- Lightweight frame model exercises addon startup, UI rendering and events.
local methods={}
local noop=function() end
local function widget()
    return setmetatable({scripts={},TitleText={SetText=noop}}, {__index=methods})
end
for _,method in ipairs({"SetPoint","ClearAllPoints","SetSize","SetWidth","SetHeight","SetJustifyH",
    "SetClampedToScreen","SetMovable","EnableMouse","RegisterForDrag","RegisterEvent",
    "StartMoving","StopMovingOrSizing","SetOwner","AddLine","SetScale","SetAutoFocus",
    "SetHighlightTexture","SetEnabled","ClearFocus","SetMaxLines"}) do methods[method]=noop end
function methods:GetStringHeight() return 45 end
function methods:GetText() return self.text or "" end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:CreateFontString() return widget() end
function methods:SetText(value) self.text=value end
function methods:SetChecked(value) self.checked=value end
function methods:GetChecked() return self.checked end
function methods:SetShown(value) self.shown=value end
function methods:Hide() self.shown=false end
function methods:Show() self.shown=true end
function methods:IsShown() return self.shown end
function methods:SetScrollChild(child) self.child=child end
local frames={}
CreateFrame=function() local f=widget(); frames[#frames+1]=f; return f end
UIParent=widget(); UISpecialFrames={}; SlashCmdList={}
local combat=false
InCombatLockdown=function() return combat end
local timers={}
C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
DEFAULT_CHAT_FRAME={AddMessage=noop}
GetBuildInfo=function() return "1.60.1","12345","date",16001 end
IsShiftKeyDown=function() return false end
GameTooltip=widget()
UnitGUID=function() return "Player-Test" end
UnitRace=function() return "Human","Human",1 end
UnitClass=function() return "Warrior","WARRIOR",1 end
LOAD_UI_CORE()
local events=frames[#frames]
TEST_EVENTS=events
test("addon initializes, registers command and renders real UI code",function()
    events.scripts.OnEvent(events,"ADDON_LOADED","ForeverQuestRoute")
    assert(A.ready and SlashCmdList.FOREVERQUESTROUTE and #UISpecialFrames==1)
    A.view.tab="route"
    A:Refresh(); assert(not A.lastError and #A.route==2)
    assert(A.rows[1].title.text and A.summary.text:find("Zona de teste",1,true))
end)
test("settings commands persist and invalid values are rejected",function()
    A:Command("drop 1 35"); assert(A.db.quests[1].dropRate==.35)
    A:Command("drop 1 0"); assert(A.db.quests[1].dropRate==.35)
    A:Command("drop 1 limpar"); assert(A.db.quests[1].dropRate==nil)
    A:Command("ignorar 1"); assert(A.db.quests[1].ignored and #A.route==1)
    A:Command("restaurar 1"); assert(not A.db.quests[1].ignored and #A.route==2)
    A:Command("grupo 1 sim"); assert(#A.route==1)
    A:Command("grupo 1 limpar"); assert(#A.route==2)
end)
test("combat defers scans; events debounce",function()
    combat=true; A:Refresh(); assert(A.dirty and not A.refreshing)
    combat=false
    A.scheduled=false; timers={}
    A:Schedule(); A:Schedule(); assert(#timers==1)
    timers[1](); assert(not A.scheduled and not A.lastError)
end)
test("navigation sets map pin and supertracking",function()
    local pin,tracked
    UiMapPoint={CreateFromCoordinates=function(m,x,y) return {map=m,x=x,y=y} end}
    C_Map.SetUserWaypoint=function(p) pin=p end
    C_SuperTrack={SetSuperTrackedUserWaypoint=function(v) tracked=v end}
    A:Navigate(quest(1)); assert(pin.map==10 and pin.x==.4 and tracked)
    pin=nil; combat=true; A:Navigate(quest(1)); assert(pin==nil); combat=false
end)
print("TOTAL " .. passes .. " tests passed")
