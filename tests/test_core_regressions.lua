local A=TEST_ADDON
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS core regression: " .. name) end

test("damaged saved settings repair without discarding character history",function()
    local db=A.db
    local saved=ForeverQuestRouteDB
    local history={completed={[9001]=true}}
    ForeverQuestRouteDB={options={solo="invalid",limit=-5,maxAbove=999,maxBelow=0/0,uiScale="invalid"},
        quests={[1]={dropRate=2,ignored="yes",group=true},[2]=true},characters={example=history},
        position={"INVALID","CENTER",0,0}}
    A:InitializeDatabase()
    assert(A.db.options.solo==true and A.db.options.limit==1 and A.db.options.maxAbove==80)
    assert(A.db.options.maxBelow==A.Engine.defaults.maxBelow and A.db.options.uiScale==1)
    assert(not A.db.quests[1].dropRate and not A.db.quests[1].ignored and A.db.quests[1].group)
    assert(A.db.quests[2]==nil and A.db.position==nil)
    assert(A.db.characters.example==history and history.completed[9001])
    ForeverQuestRouteDB=saved; A.db=db
end)

test("non table saved data recovers to a usable database",function()
    local db=A.db; local saved=ForeverQuestRouteDB
    ForeverQuestRouteDB="damaged"
    A:InitializeDatabase()
    assert(type(A.db)=="table" and type(A.db.characters)=="table" and A.db.schemaVersion==2)
    ForeverQuestRouteDB=saved; A.db=db
end)

test("route limit command rejects infinity and fractional limits",function()
    local limit=A.db.options.limit
    A:Command("limite 12"); assert(A.db.options.limit==12)
    A:Command("limite 1e309"); assert(A.db.options.limit==12)
    A:Command("limite 2.5"); assert(A.db.options.limit==12)
    A.db.options.limit=limit
end)

test("scale command is bounded and screen constrained",function()
    local parent=UIParent; local oldScale=A.frame.SetScale
    local scale
    UIParent={GetWidth=function() return 824 end,GetHeight=function() return 704 end}
    A.frame.SetScale=function(_,value) scale=value end
    A:Command("escala 150")
    assert(A.db.options.uiScale==1.5 and scale==.8)
    A:Command("escala 999"); assert(A.db.options.uiScale==1.5)
    UIParent=parent; A.frame.SetScale=oldScale; A.db.options.uiScale=1
end)

test("duplicate addon loaded event does not recreate interface or database",function()
    local frame,db=A.frame,A.db
    local count=#UISpecialFrames
    TEST_EVENTS.scripts.OnEvent(TEST_EVENTS,"ADDON_LOADED","ForeverQuestRoute")
    assert(A.frame==frame and A.db==db and #UISpecialFrames==count)
end)

test("manual refresh retries missing optional catalog provider",function()
    local ready,loading,start=A.Catalog.ready,A.Catalog.loading,A.Catalog.Start
    local calls=0
    A.Catalog.ready=false; A.Catalog.loading=false
    A.Catalog.Start=function() calls=calls+1 end
    A:Command("atualizar"); assert(calls==1)
    A.Catalog.ready=ready; A.Catalog.loading=loading; A.Catalog.Start=start
end)

test("hidden planner skips global routing while the objective tracker refreshes",function()
    local recommendations,render,tracker=A.Catalog.Recommendations,A.Render,A.RenderTracker
    local wasShown=A.frame:IsShown()
    local plans,draws,hud=0,0,0
    A.Catalog.Recommendations=function(_,_,quests) plans=plans+1; return quests end
    A.Render=function() draws=draws+1 end
    A.RenderTracker=function() hud=hud+1 end
    A.frame:Hide(); A:Refresh()
    assert(plans==0 and draws==0 and hud==1)
    A:Refresh(true); assert(plans==1 and draws==0 and hud==2)
    A.Catalog.Recommendations=recommendations; A.Render=render; A.RenderTracker=tracker
    A.frame:SetShown(wasShown)
end)

test("combat updates objective widgets without invoking planner scans",function()
    local combat,tracker,sync=InCombatLockdown,A.RenderTracker,A.Catalog.SyncCharacter
    local wasShown=A.frame:IsShown(); local hud=0
    InCombatLockdown=function() return true end
    A.RenderTracker=function() hud=hud+1 end
    A.Catalog.SyncCharacter=function() error("planner scan during combat") end
    A.frame:Hide(); A:Refresh()
    assert(hud==1 and A.dirty and not A.refreshing)
    InCombatLockdown=combat; A.RenderTracker=tracker; A.Catalog.SyncCharacter=sync
    A.frame:SetShown(wasShown)
end)

test("actual compact tracker reflects kills and ready to turn in during combat",function()
    local combat=InCombatLockdown
    local count,info,objectives,complete=C_QuestLog.GetNumQuestLogEntries,C_QuestLog.GetInfo,
        C_QuestLog.GetQuestObjectives,C_QuestLog.IsComplete
    local visible=A.trackerFrame:IsShown()
    local done=3
    InCombatLockdown=function() return true end
    C_QuestLog.GetNumQuestLogEntries=function() return 1 end
    C_QuestLog.GetInfo=function() return {questID=98765,title="Combat objective",level=20} end
    C_QuestLog.GetQuestObjectives=function() return {{text="Targets: " .. done .. "/8",numRequired=8,numFulfilled=done}} end
    C_QuestLog.IsComplete=function() return done==8 end
    A.trackerPage=1; A.trackerFrame:Show(); A:Refresh()
    assert(A.trackerRows[1].objectives.text:find("3/8",1,true))
    done=8; A:Refresh()
    assert(A.trackerRows[1].progress.text:find("Pronta para entregar",1,true))
    InCombatLockdown=combat
    C_QuestLog.GetNumQuestLogEntries=count; C_QuestLog.GetInfo=info
    C_QuestLog.GetQuestObjectives=objectives; C_QuestLog.IsComplete=complete
    A.trackerFrame:SetShown(visible)
end)

test("focus can be explicitly cleared without deleting favorites",function()
    local store=A.Tracker:Store(); local focus=store.focus
    A.Tracker:SetFocus(98765); A:Command("foco limpar")
    assert(A.Tracker:GetFocus()==nil)
    A.Tracker:SetFocus(focus)
end)

print("TOTAL " .. passed .. " core regression tests passed")
