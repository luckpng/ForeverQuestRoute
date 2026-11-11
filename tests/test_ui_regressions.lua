local A=TEST_ADDON
local oldTracker,oldViews,oldView,oldContext,oldLast=A.Tracker,A.db.views,A.view,A.context,A.db.lastTab
local oldRenderTracker,oldRefresh=A.RenderTracker,A.Refresh
local favorite,tracked,focused={},{},nil
local source={}
for i=1,9 do
    source[i]={quest={id=8000+i,title=i==1 and "Missao Acao" or "Missao " .. i,
        level=20,accepted=true,mapID=10,x=.4,y=.4},state=i==1 and "turnin" or "active",
        reason="Zona distante",progress={text="1/2 objetivos"}}
end
A.Tracker={Snapshot=function() return source end,IsFavorite=function(_,id) return favorite[id] end,
    ToggleFavorite=function(_,id) favorite[id]=not favorite[id] end,
    IsTracked=function(_,id) return tracked[id] end,
    SetTracked=function(_,id,value) tracked[id]=value; return true end,
    GetFocus=function() return focused end,SetFocus=function(_,id) focused=id end,
    Objectives=function() return {{text="Colete o item",finished=false}},{text="1/2 objetivos"} end}
A.RenderTracker=function() end
A.Refresh=function() A:Render() end
A.db.views={}; A.view=nil; A.context={mapID=10,level=20,name="Zona de teste"}
local count=0
local function test(name,fn) fn(); count=count+1; print("PASS UI regression: " .. name) end

test("journal lists accepted quests without a global database",function()
    A:SelectTab("tracker")
    assert(#A.entries==9 and A.pages==2)
    assert(A.rows[1].title.text:find("> ",1,true))
    assert(A.detailBody.text:find("Colete o item",1,true))
end)
test("tab filters are independent and remembered",function()
    A.view.search="Missao 2"; A:Render()
    A:SelectTab("route"); assert(A.view.search=="")
    A.view.search="outra busca"
    A:SelectTab("tracker"); assert(A.view.search=="Missao 2" and #A.entries==1)
end)
test("reset actually clears the current tab without changing others",function()
    A.resetButton.scripts.OnClick(A.resetButton)
    assert(A.view.tab=="tracker" and A.view.search=="" and #A.entries==9)
    assert(A.db.views.route.search=="outra busca")
end)
test("pagination keeps selected details on the visible page",function()
    A.nextPage.scripts.OnClick(A.nextPage)
    assert(A.page==2 and A.selected.quest.id==8007)
    assert(A.rows[1].title.text:find("> ",1,true))
    A.frame.scripts.OnMouseWheel(A.frame,1)
    assert(A.page==1 and A.selected.quest.id==8001)
end)
test("favorites and focus actions target the selected quest",function()
    A.favoriteButton.scripts.OnClick(A.favoriteButton)
    assert(favorite[8001] and A.favoriteButton.text=="Remover favorito")
    A.focusButton.scripts.OnClick(A.focusButton); assert(focused==8001)
    A.favoritesButton.scripts.OnClick(A.favoritesButton)
    assert(#A.entries==1 and A.entries[1].quest.id==8001)
    A.favoriteButton.scripts.OnClick(A.favoriteButton)
    assert(#A.entries==0 and A.empty.text:find("Nenhum favorito",1,true))
    A.resetButton.scripts.OnClick(A.resetButton)
end)
test("native tracking toggles from current watch state",function()
    local refresh=A.Refresh; A.Refresh=function() A:Render() end
    A.trackButton.scripts.OnClick(A.trackButton); assert(tracked[8001])
    A.trackButton.scripts.OnClick(A.trackButton); assert(not tracked[8001])
    A.Refresh=refresh
end)
test("journal status distinguishes turnins and active objectives",function()
    A.view.status="turnin"; A:Render(); assert(#A.entries==1)
    A.view.status="active"; A:Render(); assert(#A.entries==8)
    A.view.status="all"; A:Render(); assert(#A.entries==9)
end)
test("invalid persisted filters recover without rendering errors",function()
    A.db.views.history={sort="broken",status="broken",search=false,myCharacter="broken"}
    A:SelectTab("history")
    assert(A.view.sort=="status" and A.view.status=="pending" and A.view.search=="" and A.view.myCharacter==true)
end)

test("typed search debounces and stale callbacks cannot render another tab",function()
    local render,timer=A.Render,C_Timer.After
    local callbacks,renders={},0
    A.Render=function() renders=renders+1 end
    C_Timer.After=function(delay,fn) assert(delay==.12); callbacks[#callbacks+1]=fn end
    A.search:SetText("primeira"); A.search.scripts.OnTextChanged(A.search,true)
    A.search:SetText("segunda"); A.search.scripts.OnTextChanged(A.search,true)
    assert(renders==0 and #callbacks==2)
    callbacks[1](); assert(renders==0)
    callbacks[2](); assert(renders==1)
    A.search:SetText("terceira"); A.search.scripts.OnTextChanged(A.search,true)
    A:SelectTab("route"); local afterSwitch=renders
    callbacks[3](); assert(renders==afterSwitch)
    A.search:SetText(""); A.search.scripts.OnTextChanged(A.search,false)
    assert(renders==afterSwitch+1)
    A.Render=render; C_Timer.After=timer
    A.db.views.tracker=nil; A.view=nil; A:SelectTab("tracker")
end)

test("opening a compact tracker quest clears hiding filters and reveals its page",function()
    A.view.status="turnin"; A.view.search="sem resultado"; A.view.favoritesOnly=true
    A:Render(); assert(#A.entries==0)
    assert(A:OpenJournalQuest(8008))
    assert(A.view.tab=="tracker" and A.view.search=="" and A.view.status=="all" and not A.view.favoritesOnly)
    assert(A.page==2 and A.selected.quest.id==8008 and A.rows[2].entry.quest.id==8008)
end)

test("focused quest can be cleared using the same action",function()
    A.focusButton.scripts.OnClick(A.focusButton)
    assert(focused==8008 and A.focusButton.text=="Limpar foco da quest")
    A.focusButton.scripts.OnClick(A.focusButton)
    assert(focused==nil and A.focusButton.text=="Focar quest selecionada")
end)

test("turnin navigation preserves a known delivery when native waypoint is absent",function()
    local location,waypoint=A.Catalog.Location,C_QuestLog.GetNextWaypoint
    local oldRecord=A.Catalog.byID[9900]
    local record={id=9900,title="Entrega conhecida"}; A.Catalog.byID[9900]=record
    A.Catalog.Location=function() return "Entregador",{mapID=42,x=.3,y=.7,title="Entrega conhecida"} end
    C_QuestLog.GetNextWaypoint=function() return nil end
    local entry={quest={id=9900,title=record.title,accepted=true},state="turnin"}
    A:ShowDetails(entry)
    assert(entry.point and entry.point.mapID==42 and entry.point.x==.3)
    entry.state="active"; A:ShowDetails(entry)
    assert(entry.point==nil)
    A.Catalog.Location=location; C_QuestLog.GetNextWaypoint=waypoint; A.Catalog.byID[9900]=oldRecord
end)

test("favorite and focus reorder recommended quests immediately",function()
    local context,collect,recommend,sync,lastMap=A.Context,A.Collect,A.Catalog.Recommendations,A.Catalog.SyncCharacter,A.lastMap
    local oldRoute,oldQuests,oldExcluded=A.route,A.quests,A.excluded
    local oldShown=A.frame:IsShown()
    local candidates={
        {id=9001,title="Primeira",accepted=true,level=20,mapID=10,x=.4,y=.4,objectives={}},
        {id=9002,title="Segunda",accepted=true,level=20,mapID=10,x=.4,y=.4,objectives={}},
    }
    A.Context=function() return {mapID=10,level=20,name="Teste",position={x=.4,y=.4},aspect=1} end
    A.Collect=function() return candidates end
    A.Catalog.Recommendations=function(_,_,qs) return qs end
    A.Catalog.SyncCharacter=function() end
    A.lastMap=10; A.frame:Show()
    A.db.views.route=nil; A.view=nil; A:SelectTab("route")
    A.Refresh=oldRefresh; A:Refresh()
    assert(A.route[1].id==9001)
    A.rows[2].scripts.OnClick(A.rows[2])
    A.favoriteButton.scripts.OnClick(A.favoriteButton)
    assert(A.route[1].id==9002)
    A.rows[2].scripts.OnClick(A.rows[2])
    A.focusButton.scripts.OnClick(A.focusButton)
    assert(A.route[1].id==9001 and focused==9001)
    A.Context=context; A.Collect=collect; A.Catalog.Recommendations=recommend; A.Catalog.SyncCharacter=sync; A.lastMap=lastMap
    A.route=oldRoute; A.quests=oldQuests; A.excluded=oldExcluded; A.frame:SetShown(oldShown)
    A.Refresh=function() A:Render() end
end)

A.Tracker=oldTracker; A.db.views=oldViews; A.view=oldView; A.context=oldContext; A.db.lastTab=oldLast
A.RenderTracker=oldRenderTracker; A.Refresh=oldRefresh
A:Render()
print("TOTAL " .. count .. " UI regression tests passed")
