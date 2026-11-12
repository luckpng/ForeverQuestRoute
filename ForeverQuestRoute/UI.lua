local _, A = ...
local PAGE_SIZE=6
local statusNames={all="Todas",pending="Pendentes",done="Concluidas",active="Em andamento",turnin="Entregar",available="Sem bloqueios",locked="Bloqueadas",verify="Ver requisitos"}
local tabNames={area="Area atual",tracker="Meu diario",route="Recomendadas",dungeons="Dungeons",history="Catalogo / Historico"}
local function defaults(tab)
    return {tab=tab,status=tab=="tracker" and "all" or "pending",search="",myCharacter=true,levelOnly=false,
        areaDungeons=false,areaRepeatables=false,favoritesOnly=false,sort=(tab=="route" or tab=="tracker") and "suggested" or "status"}
end
local function tooltip(widget,text)
    widget:SetScript("OnEnter",function(b) GameTooltip:SetOwner(b,"ANCHOR_RIGHT"); GameTooltip:SetText(text); GameTooltip:Show() end)
    widget:SetScript("OnLeave",function() GameTooltip:Hide() end)
end
local colors={done="|cff67df9b",active="|cff78c9ff",turnin="|cffffd46b",locked="|cffffa07b",
    restricted="|cffaaaaaa",unknown="|cffaaaaaa",pending="|cffe8e4dc",verify="|cffffc27b"}
local names={done="Concluida",active="Em andamento",turnin="Entregar",locked="Bloqueada",
    restricted="Outra raca/classe",unknown="Sem status",pending="Pendente",verify="Ver requisitos"}
local function label(parent,font,x,y,w)
    local s=parent:CreateFontString(nil,"OVERLAY",font)
    s:SetPoint("TOPLEFT",x,y); s:SetWidth(w); s:SetJustifyH("LEFT"); return s
end
local function button(parent,title,x,y,w,click)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT",x,y); b:SetSize(w,24); b:SetText(title); b:SetScript("OnClick",click); return b
end
local function check(parent,title,x,y,click)
    local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate")
    b:SetPoint("TOPLEFT",x,y)
    local t=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    t:SetPoint("LEFT",b,"RIGHT",0,0); t:SetText(title)
    b:SetScript("OnClick",click); return b
end
function A:SelectTab(tab)
    if not tabNames[tab] then return end
    self.searchGeneration=(self.searchGeneration or 0)+1
    self.db.views=type(self.db.views)=="table" and self.db.views or {}
    if self.view then self.db.views[self.view.tab]=self.view end
    local view=defaults(tab)
    local stored=type(self.db.views[tab])=="table" and self.db.views[tab] or {}
    for key,value in pairs(stored) do if view[key]~=nil and type(value)==type(view[key]) then view[key]=value end end
    if type(stored.dungeonID)=="number" and self.Catalog.dungeons[stored.dungeonID] then view.dungeonID=stored.dungeonID end
    view.tab=tab
    if not statusNames[view.status] then view.status=tab=="tracker" and "all" or "pending" end
    if type(view.search)~="string" then view.search="" end
    if not ({suggested=true,status=true,level=true,title=true})[view.sort] then view.sort="status" end
    if tab=="tracker" and not ({all=true,active=true,turnin=true})[view.status] then view.status="all" end
    self.view=view; self.db.views[tab]=view; self.db.lastTab=tab
    self.page=1; self.selected=nil
    if self.search then self.search:SetText(view.search) end
    self:Render()
end
-- Reveal a quest explicitly chosen in the compact tracker, regardless of saved filters.
function A:OpenJournalQuest(id)
    if type(id)~="number" or id<=0 or id%1~=0 then return false end
    self:SelectTab("tracker")
    self.view.status="all"; self.view.search=""; self.view.favoritesOnly=false; self.view.sort="suggested"
    self.search:SetText("")
    self.frame:Show(); self:Refresh(); self:Render()
    for index,entry in ipairs(self.entries or {}) do
        if entry.quest.id==id then
            self.page=math.ceil(index/PAGE_SIZE); self.selected=entry; self:Render(); return true
        end
    end
    return false
end
function A:CreateUI()
    self.db.views=type(self.db.views)=="table" and self.db.views or {}
    self.view=nil; self.page=1
    self:SelectTab(tabNames[self.db.lastTab] and self.db.lastTab or "area")
    local f=CreateFrame("Frame","ForeverQuestRouteFrame",UIParent,"BasicFrameTemplateWithInset")
    self.frame=f; f:SetSize(1000,680); f:SetPoint("CENTER"); f:SetClampedToScreen(true)
    if UIParent.GetWidth and UIParent.GetHeight then
        f:SetScale(math.max(.5,math.min(1,(UIParent:GetWidth()-24)/1000,(UIParent:GetHeight()-24)/680)))
    end
    if self.ApplyUIScale then self:ApplyUIScale() end
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function() f:StartMoving() end)
    f:SetScript("OnDragStop",function()
        f:StopMovingOrSizing(); local p,_,rp,x,y=f:GetPoint(); self.db.position={p,rp,x,y}
    end)
    local p=self.db.position
    if p then f:ClearAllPoints(); f:SetPoint(p[1],UIParent,p[2],p[3],p[4]) end
    f.TitleText:SetText("Forever Quest Route  |  Planejador de aventuras")
    table.insert(UISpecialFrames,"ForeverQuestRouteFrame")
    self.tabs={}
    for i,entry in ipairs({{"area","Area atual"},{"tracker","Meu diario"},{"route","Recomendadas"},{"dungeons","Dungeons"},{"history","Catalogo / Historico"}}) do
        local tab=entry[1]
        self.tabs[tab]=button(f,entry[2],16+(i-1)*140,-35,132,function() self:SelectTab(tab) end)
    end
    button(f,"Atualizar",865,-35,115,function()
        if not self.Catalog.ready then self.Catalog:Start() end
        self:RequestMap(self:Context().mapID); self:Refresh()
    end)
    self.sortButton=button(f,"Ordenar: Status",716,-35,139,function()
        local order=(self.view.tab=="route" or self.view.tab=="tracker") and {"suggested","status","level","title"} or {"status","level","title"}
        local index=1; for i,value in ipairs(order) do if value==self.view.sort then index=i%#order+1 end end
        self.view.sort=order[index]; self.page=1; self:Render()
    end)
    tooltip(self.sortButton,"Alterna a ordem da lista. A rota sugerida considera proximidade e esforco.")
    self.summary=label(f,"GameFontNormal",18,-75,960)
    label(f,"GameFontHighlightSmall",18,-110,80):SetText("Nome ou ID:")
    local search=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
    search:SetSize(230,24); search:SetPoint("TOPLEFT",100,-103); search:SetAutoFocus(false)
    search:SetScript("OnTextChanged",function(box,userInput)
        self.view.search=box:GetText(); self.page=1
        self.searchGeneration=(self.searchGeneration or 0)+1
        local generation,view=self.searchGeneration,self.view
        if userInput and C_Timer and C_Timer.After then
            C_Timer.After(.12,function()
                if self.searchGeneration==generation and self.view==view then self:Render() end
            end)
        else self:Render() end
    end)
    search:SetScript("OnEscapePressed",function(box) box:ClearFocus() end)
    search:SetScript("OnEnterPressed",function(box)
        self.searchGeneration=(self.searchGeneration or 0)+1
        box:ClearFocus(); self:Render()
    end); self.search=search
    self.clearSearch=button(f,"X",337,-103,27,function() self.search:SetText(""); self.view.search=""; self.page=1; self:Render() end)
    tooltip(self.clearSearch,"Limpar busca. Busque por nome, palavras ou ID da quest.")
    self.statusButton=button(f,"Status: Pendentes",380,-103,180,function()
        local order=self.view.tab=="tracker" and {"all","active","turnin"} or {"pending","active","turnin","available","locked","verify","done","all"}
        local index=1; for i,value in ipairs(order) do if value==self.view.status then index=i%#order+1 end end
        self.view.status=order[index]
        self.page=1; self:Render()
    end)
    self.levelCheck=check(f,"Meu nivel",575,-99,function(b) self.view.levelOnly=b:GetChecked() and true or false; self.page=1; self:Render() end)
    self.charCheck=check(f,"Minha raca/classe",735,-99,function(b) self.view.myCharacter=b:GetChecked() and true or false; self.page=1; self:Render() end)
    self.itemCheck=check(f,"Menos coleta",575,-99,function(b) self.db.options.avoidItems=b:GetChecked() and true or false; self:Refresh() end)
    self.soloCheck=check(f,"Solo",735,-99,function(b) self.db.options.solo=b:GetChecked() and true or false; self:Refresh() end)
    self.areaDungeonCheck=check(f,"Incluir dungeons",575,-99,function(b)
        self.view.areaDungeons=b:GetChecked() and true or false; self.page=1; self:Render()
    end)
    self.areaRepeatCheck=check(f,"Incluir repetiveis",770,-99,function(b)
        self.view.areaRepeatables=b:GetChecked() and true or false; self.page=1; self:Render()
    end)
    tooltip(self.statusButton,"Alterna o status. Pendentes inclui quests bloqueadas; Sem bloqueios inclui requisitos conhecidos atendidos; confirme a disponibilidade no jogo.")
    self.sidebarTitle=label(f,"GameFontNormal",18,-145,215)
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",16,-169); scroll:SetSize(200,380)
    local side=CreateFrame("Frame",nil,scroll); side:SetSize(195,1); scroll:SetScrollChild(side)
    self.sideContent,self.sideRows=side,{}; self.sideInfo=label(side,"GameFontHighlightSmall",4,-5,185)
    self.listTitle=label(f,"GameFontNormal",254,-145,725); self.empty=label(f,"GameFontHighlight",260,-190,695)
    self.rows={}
    for i=1,PAGE_SIZE do
        local row=CreateFrame("Button",nil,f)
        row:SetPoint("TOPLEFT",250,-174-(i-1)*43); row:SetSize(728,42)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.title=label(row,"GameFontNormal",8,-3,532); row.title:SetMaxLines(1)
        row.status=label(row,"GameFontHighlightSmall",550,-5,173)
        row.subtitle=label(row,"GameFontDisableSmall",8,-23,710)
        row.subtitle:SetMaxLines(1)
        row:SetScript("OnClick",function(b)
            if not b.entry then return end
            if self.view.tab=="route" and IsShiftKeyDown() then
                local q=b.entry.quest; self.db.quests[q.id]=self.db.quests[q.id] or {}; self.db.quests[q.id].ignored=true
                self:Refresh(); return
            end
            self.selected=b.entry; self:Render()
        end)
        row:SetScript("OnEnter",function(b)
            if not b.entry then return end
            GameTooltip:SetOwner(b,"ANCHOR_RIGHT"); GameTooltip:SetText(b.entry.quest.title)
            GameTooltip:AddLine(b.entry.reason or "",1,1,1,true)
            local record=self.Catalog.byID[b.entry.quest.id]
            if record and (b.entry.state=="locked" or b.entry.state=="verify") then
                local requirements=self.Catalog:Requirements(record,self.context.level)
                for _,line in ipairs(requirements) do GameTooltip:AddLine(line,1,.85,.55,true) end
            end
            GameTooltip:AddLine("Clique para ver origem, requisitos e acoes.",.7,.7,.7,true); GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end); self.rows[i]=row
    end
    self.prevPage=button(f,"< Anterior",254,-443,105,function() self.page=math.max(1,self.page-1); self.selected=nil; self:Render() end)
    self.pageText=label(f,"GameFontHighlightSmall",379,-450,385)
    self.nextPage=button(f,"Proxima >",868,-443,110,function() self.page=math.min(self.pages or 1,self.page+1); self.selected=nil; self:Render() end)
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel",function(_,delta)
        local page=math.max(1,math.min(self.pages or 1,self.page+(delta>0 and -1 or 1)))
        if page~=self.page then self.page=page; self.selected=nil; self:Render() end
    end)
    self.detailTitle=label(f,"GameFontNormal",254,-485,725)
    self.detailTitle:SetMaxLines(1)
    -- Scrollable details keep long prerequisite chains accessible.
    local detailScroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT",254,-510); detailScroll:SetSize(700,94)
    local detailContent=CreateFrame("Frame",nil,detailScroll); detailContent:SetSize(690,96)
    detailScroll:SetScrollChild(detailContent); self.detailContent=detailContent; self.detailScroll=detailScroll
    self.detailBody=label(detailContent,"GameFontHighlightSmall",0,0,680)
    self.giverButton=button(f,"Marcar coleta",254,-614,130,function()
        if self.selected and self.selected.point then self:Navigate(self.selected.point) end
    end)
    self.entranceButton=button(f,"Entrada dungeon",394,-614,145,function()
        local point=self.selected and self.Catalog:Entrance(self.selected.dungeon)
        if point then self:Navigate(point) end
    end)
    self.trackButton=button(f,"Rastrear quest",549,-614,130,function()
        local q=self.selected and self.selected.quest
        if q and (q.accepted or self.Catalog.logs and self.Catalog.logs[q.id]) then
            if self.Tracker then
                local ok,reason=self.Tracker:SetTracked(q.id,not self.Tracker:IsTracked(q.id))
                if not ok and reason then self:Print(reason) end
            else self:Call(C_QuestLog,"AddQuestWatch",q.id); self:Call(C_SuperTrack,"SetSuperTrackedQuestID",q.id) end
            self:Refresh()
        end
    end)
    self.previousButton=button(f,"Ver pre-requisito",689,-614,150,function()
        local record=self.selected and self.Catalog.byID[self.selected.quest.id]
        local id=record and self.Catalog:FirstMissing(record)
        if id and self.Catalog.byID[id] then
            self:SelectTab("history"); self.view.status="all"; self.view.levelOnly=false
            self.view.myCharacter=false; self.view.favoritesOnly=false
            self.view.dungeonID=nil; self.selected=nil; self.page=1
            self.search:SetText(tostring(id)); self.view.search=tostring(id); self:Render()
        end
    end)
    self.favoriteButton=button(f,"Favoritar",849,-614,130,function()
        if self.selected and self.Tracker then self.Tracker:ToggleFavorite(self.selected.quest.id); self:Refresh() end
    end)
    self.focusButton=button(f,"Focar quest selecionada",18,-553,198,function()
        if self.selected and self.Tracker then
            local id=self.selected.quest.id
            if self.Tracker:GetFocus()==id then self.Tracker:SetFocus(nil) else self.Tracker:SetFocus(id) end
            self:Refresh()
        end
    end)
    self.compactButton=button(f,"Mostrar tracker compacto",18,-584,198,function() if self.ToggleTracker then self:ToggleTracker() end end)
    self.resetButton=button(f,"Limpar filtros",18,-614,198,function()
        local tab=self.view.tab; self.db.views[tab]=nil; self.view=nil; self:SelectTab(tab)
    end)
    self.favoritesButton=button(f,"Favoritos: Todos",18,-644,198,function()
        self.view.favoritesOnly=not self.view.favoritesOnly; self.page=1; self:Render()
    end)
    tooltip(self.focusButton,"Prioriza a quest selecionada no tracker compacto. O foco e salvo por personagem.")
    tooltip(self.favoriteButton,"Salva esta quest nos favoritos deste personagem.")
    tooltip(self.trackButton,"Adiciona ou remove a quest do acompanhamento nativo do jogo.")
    tooltip(self.giverButton,"Marca no mapa a origem, proximo objetivo ou entrega conhecida.")
    tooltip(self.resetButton,"Restaura os filtros padrao desta aba. Seus favoritos e progresso sao preservados.")
    self.footer=label(f,"GameFontDisableSmall",254,-654,725)
    f:SetScript("OnShow",function() if self.ready then self:Refresh() end end)
    f:SetScript("OnHide",function() self.searchGeneration=(self.searchGeneration or 0)+1 end); f:Hide()
end
function A:ShowDetails(entry)
    if not entry then
        self.detailTitle:SetText("Selecione uma quest para planejar o proximo passo")
        self.detailBody:SetText("Veja onde aceitar, quais pre-requisitos faltam e marque a entrada da dungeon.")
        self.giverButton:SetEnabled(false); self.entranceButton:SetEnabled(false); self.trackButton:SetEnabled(false)
        self.previousButton:SetEnabled(false); self.favoriteButton:SetEnabled(false); self.focusButton:SetEnabled(false)
        self.favoriteButton:SetText("Favoritar"); return
    end
    local q=entry.quest; local record=self.Catalog.byID[q.id]
    self.detailTitle:SetText(q.title .. "  |  #" .. q.id)
    local pieces={entry.reason or ""}
    if self.Tracker and (q.accepted or (self.Catalog.logs and self.Catalog.logs[q.id])) then
        local objectives,progress=self.Tracker:Objectives(q.id)
        if progress and progress.text then pieces[#pieces+1]="OBJETIVOS  |  " .. progress.text end
        for _,objective in ipairs(objectives or {}) do
            pieces[#pieces+1]=(objective.finished and "[OK] " or "[ ] ") .. (objective.text or "Objetivo")
        end
    end
    if record then
        local requirements=self.Catalog:Requirements(record,self.context.level)
        if #requirements>0 then pieces[#pieces+1]="PRE-REQUISITOS\n" .. table.concat(requirements,"\n") end
        local origin,point=self.Catalog:Location(record,entry.state=="turnin"); entry.point=point
        pieces[#pieces+1]=(entry.state=="turnin" and "Entregar: " or ((q.accepted or self.Catalog.logs and self.Catalog.logs[q.id]) and "Origem da quest: " or "Aceitar: ")) .. origin
        if record.dungeonSource then pieces[#pieces+1]="Vinculo com a dungeon: " .. record.dungeonSource end
    else
        entry.point=q
        pieces[#pieces+1]=q.x and q.y and "Coordenadas do proximo objetivo fornecidas pelo jogo."
            or "O jogo nao forneceu coordenadas para o proximo objetivo."
    end
    self.detailBody:SetText(table.concat(pieces,"\n"))
    self.detailContent:SetHeight(math.max(96,self.detailBody:GetStringHeight()+8))
    if self.detailQuestID~=q.id and self.detailScroll.SetVerticalScroll then self.detailScroll:SetVerticalScroll(0) end
    self.detailQuestID=q.id
    self.favoriteButton:SetEnabled(self.Tracker~=nil)
    self.favoriteButton:SetText(self.Tracker and self.Tracker:IsFavorite(q.id) and "Remover favorito" or "Favoritar")
    self.focusButton:SetEnabled(self.Tracker~=nil and (q.accepted or (self.Catalog.logs and self.Catalog.logs[q.id])) and true or false)
    self.focusButton:SetText(self.Tracker and self.Tracker:GetFocus()==q.id and "Limpar foco da quest" or "Focar quest selecionada")
    entry.tracked=self.Tracker and self.Tracker:IsTracked(q.id) or entry.tracked
    self.trackButton:SetText(entry.tracked and "Parar de rastrear" or "Rastrear quest")
    self.giverButton:SetText(entry.state=="turnin" and "Marcar entrega" or (q.accepted and "Marcar objetivo" or "Marcar coleta"))
    if q.accepted or self.Catalog.logs and self.Catalog.logs[q.id] then
        local map,x,y=self:Call(C_QuestLog,"GetNextWaypoint",q.id)
        local delivery=entry.state=="turnin" and record and entry.point
        entry.point=nil
        if type(map)=="number" and map>0 and type(x)=="number" and type(y)=="number" and x>=0 and x<=1 and y>=0 and y<=1 then
            entry.point={mapID=map,x=x,y=y,title=q.title}
        elseif q.mapID and q.x and q.y then entry.point=q
        elseif delivery then entry.point=delivery end
        if not entry.point and self.Tracker and self.Tracker.ResolveDestination then
            local objectives=self.Tracker:Objectives(q.id)
            entry.point=self.Tracker:ResolveDestination({quest={id=q.id,title=q.title,
                complete=entry.state=="turnin",objectives=objectives}},self.context)
        end
        self.giverButton:SetText(entry.state=="turnin" and "Marcar entrega" or "Marcar objetivo")
    end
    if entry.point and entry.point.source then
        pieces[#pieces+1]=entry.point.source
        self.detailBody:SetText(table.concat(pieces,"\n"))
        self.detailContent:SetHeight(math.max(96,self.detailBody:GetStringHeight()+8))
    end
    self.giverButton:SetEnabled(entry.point and entry.point.mapID and entry.point.x and entry.point.y and true or false)
    self.entranceButton:SetEnabled(self.Catalog:Entrance(entry.dungeon)~=nil)
    self.trackButton:SetEnabled(q.accepted or self.Catalog.logs and self.Catalog.logs[q.id]~=nil or false)
    local previous=record and self.Catalog:FirstMissing(record)
    self.previousButton:SetEnabled(previous and self.Catalog.byID[previous]~=nil or false)
end
function A:RenderSidebar()
    for _,row in ipairs(self.sideRows) do row:Hide() end
    self.sideInfo:Hide()
    if self.view.tab=="area" then
        local s=self.areaStats
        self.sidebarTitle:SetText("Progresso da area")
        self.sideContent:SetHeight(430); self.sideInfo:Show()
        self.sideInfo:SetText(self.context.name .. string.format("\n\n%d / %d concluidas (%d%%)\nFaltam %d\n\n%d prontas para entregar\n%d em andamento\n%d pendentes\n%d bloqueadas\n%d requisitos especiais\n%d sem status\n\nFora do total:\n%d repetiveis\n%d de dungeon\n%d alternativas/expiradas\n\nTotal da base, por personagem. Busca e Status nao alteram o progresso.",
            s.done,s.total,s.percent,s.remaining,s.turnin,s.active,s.pending,s.locked,s.verify,s.unknown,
            s.repeatables,s.dungeons,s.excluded))
        return
    end
    if self.view.tab=="tracker" then
        self.sideContent:SetHeight(260); self.sideInfo:Show(); self.sidebarTitle:SetText("Seu diario de quests")
        self.sideInfo:SetText("Todas as quests aceitas por este personagem, inclusive em outras zonas.\n\n[+] indica favorito.\n> indica a quest selecionada.\n\nUse Focar quest para priorizar uma aventura no tracker compacto.\n\nRastrear alterna o acompanhamento nativo do jogo.")
        return
    end
    if self.view.tab~="dungeons" then
        self.sideContent:SetHeight(240); self.sideInfo:Show()
        self.sidebarTitle:SetText(self.view.tab=="route" and "Sua rota" or "Historico do personagem")
        self.sideInfo:SetText(self.view.tab=="route"
            and (self.context.name .. "\nNivel " .. self.context.level .. "\n\nSelecione uma etapa e marque o objetivo.\n\nShift+clique ignora uma quest.\n\nA rota usa proximidade e esforco.\n\nQuests de dungeon ficam na aba Dungeons, inclusive fora do mapa.")
            or "Catalogo global do QuestieDB.\n\nUse Status para alternar pendentes, todas, concluidas e em andamento.\n\nConclusao e por personagem.\n\nPendente inclui quests bloqueadas por nivel ou pre-requisitos.")
        return
    end
    self.sidebarTitle:SetText("Escolha uma dungeon")
    local counts={}
    for _,q in ipairs(self.Catalog.records) do
        if q.dungeonID and (not self.view.myCharacter or self.Catalog:MatchesCharacter(q)) then
            local c=counts[q.dungeonID] or {total=0,done=0}; counts[q.dungeonID]=c
            c.total=c.total+1; if self.Catalog:Done(q.id) then c.done=c.done+1 end
        end
    end
    local items={{name="Todas as dungeons"}}
    for id,count in pairs(counts) do items[#items+1]={id=id,name=self.Catalog.dungeons[id].name,count=count} end
    table.sort(items,function(a,b) if not a.id then return b.id~=nil elseif not b.id then return false else return a.name<b.name end end)
    for i,item in ipairs(items) do
        local row=self.sideRows[i]
        if not row then
            row=CreateFrame("Button",nil,self.sideContent); row:SetSize(195,43); row:SetPoint("TOPLEFT",0,-(i-1)*44)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.title=label(row,"GameFontHighlightSmall",3,-4,190); row.info=label(row,"GameFontDisableSmall",3,-25,190)
            row.title:SetMaxLines(1)
            row:SetScript("OnClick",function(b) self.view.dungeonID=b.dungeonID; self.page=1; self.selected=nil; self:Render() end)
            self.sideRows[i]=row
        end
        row.dungeonID=item.id
        row.title:SetText((self.view.dungeonID==item.id and "|cffffd46b> " or "") .. item.name .. "|r")
        row.info:SetText(item.count and (item.count.done .. "/" .. item.count.total .. " concluidas") or "Todas as regioes")
        row:Show()
    end
    self.sideContent:SetHeight(math.max(1,#items*44))
end
function A:Render()
    if not self.frame or not self.context then return end
    local view=self.view; local routeMode=view.tab=="route"; local areaMode=view.tab=="area"; local trackerMode=view.tab=="tracker"
    self.levelCheck:SetShown(not routeMode and not areaMode and not trackerMode); self.charCheck:SetShown(not routeMode and not areaMode and not trackerMode)
    self.areaDungeonCheck:SetShown(areaMode); self.areaRepeatCheck:SetShown(areaMode)
    self.areaDungeonCheck:SetChecked(view.areaDungeons); self.areaRepeatCheck:SetChecked(view.areaRepeatables)
    self.itemCheck:SetShown(routeMode); self.soloCheck:SetShown(routeMode); self.statusButton:SetShown(not routeMode)
    self.levelCheck:SetChecked(view.levelOnly); self.charCheck:SetChecked(view.myCharacter)
    self.itemCheck:SetChecked(self.db.options.avoidItems); self.soloCheck:SetChecked(self.db.options.solo)
    self.statusButton:SetText("Status: " .. (statusNames[view.status] or "Todas") .. " >")
    self.sortButton:SetText("Ordem: " .. ({suggested=trackerMode and "Prioridade" or "Rota",status="Status",level="Nivel",title="Nome"})[view.sort or "status"])
    self.clearSearch:SetEnabled(view.search~="")
    self.favoritesButton:SetText(view.favoritesOnly and "Favoritos: Somente [+]" or "Favoritos: Todos")
    self.compactButton:SetEnabled(self.ToggleTracker~=nil)
    for key,tab in pairs(self.tabs) do tab:SetEnabled(key~=view.tab) end
    local entries,counts={},{done=0,pending=0,active=0,total=0}
    if areaMode then
        entries,counts=self.Catalog:AreaView(self.context,view); self.areaStats=counts
        self.summary:SetText(string.format("%s  |  %d/%d concluidas (%d%%)  |  Faltam %d quests da base",
            self.context.name,counts.done,counts.total,counts.percent,counts.remaining))
        self.listTitle:SetText("Quests da area atual - todos os niveis do seu personagem")
    elseif trackerMode then
        local all=self.Tracker and self.Tracker:Snapshot(self.context) or {}
        for _,entry in ipairs(all) do
            local matches
            if self.Catalog.SearchMatches then matches=self.Catalog:SearchMatches(entry.quest,view.search)
            else matches=view.search=="" or string.find(string.lower(entry.quest.title .. " " .. entry.quest.id),string.lower(view.search),1,true) end
            local status=view.status=="all" or view.status==entry.state or view.status=="active" and entry.state=="active"
            if matches and status then entries[#entries+1]=entry end
        end
        self.summary:SetText(string.format("Meu diario  |  %d quests aceitas  |  %d prontas para entregar",#all,(function() local n=0; for _,entry in ipairs(all) do if entry.state=="turnin" then n=n+1 end end; return n end)()))
        self.listTitle:SetText("Quests aceitas em todas as zonas")
    elseif routeMode then
        local search=string.lower(view.search)
        for _,q in ipairs(self.route or {}) do
            if self.Catalog.SearchMatches and self.Catalog:SearchMatches(q,view.search) or not self.Catalog.SearchMatches and (search=="" or string.find(string.lower(q.title .. " " .. q.id),search,1,true)) then
                entries[#entries+1]={quest=q,state=q.complete and "turnin" or (q.accepted and "active" or "pending"),reason=q.reason}
            end
        end
        self.summary:SetText(string.format("%s  |  Nivel %d  |  %d etapas  |  %d filtradas",self.context.name,self.context.level,#entries,self.excluded or 0))
        self.listTitle:SetText("Ordem sugerida para o mapa atual")
    else
        entries,counts=self.Catalog:View(self.context.level,view)
        self.summary:SetText(string.format("%d concluidas  |  %d pendentes  |  %d em andamento  |  %d quests no recorte",counts.done,counts.pending,counts.active,counts.total))
        local d=view.dungeonID and self.Catalog.dungeons[view.dungeonID]
        self.listTitle:SetText(d and d.name or (view.tab=="dungeons" and "Quests de dungeons em todas as regioes" or "Todas as quests do catalogo"))
    end
    if view.favoritesOnly then
        local filtered={}; for _,entry in ipairs(entries) do if self.Tracker and self.Tracker:IsFavorite(entry.quest.id) then filtered[#filtered+1]=entry end end
        entries=filtered
    end
    if view.sort~="suggested" then
        local rank={turnin=1,active=2,pending=3,verify=4,locked=5,unknown=6,done=7,restricted=8}
        table.sort(entries,function(a,b)
            if view.sort=="title" then
                local an,bn=string.lower(a.quest.title),string.lower(b.quest.title)
                if an~=bn then return an<bn end
            elseif view.sort=="status" then
                local ar,br=rank[a.state] or 9,rank[b.state] or 9; if ar~=br then return ar<br end
            end
            local al,bl=a.quest.level or 0,b.quest.level or 0
            if al~=bl then return al<bl end
            return a.quest.id<b.quest.id
        end)
    end
    self:RenderSidebar(); self.entries=entries
    self.pages=math.max(1,math.ceil(#entries/PAGE_SIZE)); self.page=math.min(self.page,self.pages)
    self.prevPage:SetEnabled(self.page>1); self.nextPage:SetEnabled(self.page<self.pages)
    self.pageText:SetText(string.format("Pagina %d/%d  |  %d resultados",self.page,self.pages,#entries))
    local selected
    if self.selected then
        for i=(self.page-1)*PAGE_SIZE+1,math.min(self.page*PAGE_SIZE,#entries) do
            local entry=entries[i]; if entry.quest.id==self.selected.quest.id then selected=entry; break end
        end
    end
    self.selected=selected or entries[(self.page-1)*PAGE_SIZE+1]
    for i,row in ipairs(self.rows) do
        local entry=entries[(self.page-1)*PAGE_SIZE+i]; row:SetShown(entry~=nil)
        if entry then
            row.entry=entry; local q=entry.quest
            local isSelected=self.selected and self.selected.quest.id==q.id
            if row.LockHighlight and row.UnlockHighlight then if isSelected then row:LockHighlight() else row:UnlockHighlight() end end
            local favorite=self.Tracker and self.Tracker:IsFavorite(q.id)
            row.title:SetText((isSelected and "> " or "") .. (favorite and "[+] " or "") .. (routeMode and (((self.page-1)*PAGE_SIZE+i) .. ". ") or "") .. q.title)
            row.status:SetText((colors[entry.state] or "") .. (names[entry.state] or "") .. "|r")
            local subtitle=entry.progress and entry.progress.text or entry.dungeon and entry.dungeon.name or (entry.reason or "")
            local record=self.Catalog.byID[q.id]
            if record and (entry.state=="locked" or entry.state=="verify") then
                local _,requirements=self.Catalog:Requirements(record,self.context.level)
                subtitle="Requer: " .. requirements
            end
            row.subtitle:SetText(string.format("Nivel %s  |  #%d  |  %s",q.level and q.level>0 and q.level or "?",q.id,subtitle))
        end
    end
    self.empty:SetShown(#entries==0)
    local emptyMessage="Nenhuma quest neste filtro. Use Limpar filtros para recomecar."
    if view.favoritesOnly then emptyMessage="Nenhum favorito neste recorte. Favorite uma quest nos detalhes ou altere Favoritos: Todos."
    elseif trackerMode and view.search=="" and view.status=="all" then emptyMessage="Seu diario esta vazio. Aceite uma quest no jogo para acompanhar os objetivos aqui."
    elseif not trackerMode and self.Catalog.loading then emptyMessage="Carregando QuestieDB... " .. self.Catalog.progress .. "/" .. self.Catalog.total
    elseif not trackerMode and not routeMode and not self.Catalog.ready then emptyMessage=self.Catalog.message or "Ative QuestieDB para carregar o catalogo."
    elseif routeMode and view.search=="" then emptyMessage="Nenhuma etapa para esta zona e faixa de nivel. Tente desmarcar Solo ou confira /fqr nivel."
    end
    self.empty:SetText(emptyMessage)
    self:ShowDetails(self.selected)
    self.footer:SetText(self.Catalog.loading and string.format("Indexando QuestieDB: %d/%d",self.Catalog.progress,self.Catalog.total)
        or (self.Catalog.message or "Rota local") .. "  |  /fqr ajuda")
end
