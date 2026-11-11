local _, A = ...
local PAGE_SIZE=6
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
    self.view.tab=tab; self.page=1; self.selected=nil; self.view.dungeonID=nil; self:Render()
end
function A:CreateUI()
    self.view={tab="area",status="pending",search="",myCharacter=true,levelOnly=false,
        areaDungeons=false,areaRepeatables=false}; self.page=1
    local f=CreateFrame("Frame","ForeverQuestRouteFrame",UIParent,"BasicFrameTemplateWithInset")
    self.frame=f; f:SetSize(1000,680); f:SetPoint("CENTER"); f:SetClampedToScreen(true)
    if UIParent.GetWidth and UIParent.GetHeight then
        f:SetScale(math.max(.5,math.min(1,(UIParent:GetWidth()-24)/1000,(UIParent:GetHeight()-24)/680)))
    end
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
    for i,entry in ipairs({{"area","Area atual"},{"route","Recomendadas"},{"dungeons","Dungeons"},{"history","Catalogo / Historico"}}) do
        local tab=entry[1]
        self.tabs[tab]=button(f,entry[2],16+(i-1)*175,-35,165,function() self:SelectTab(tab) end)
    end
    button(f,"Atualizar",865,-35,115,function()
        if not self.Catalog.ready then self.Catalog:Start() end
        self:RequestMap(self:Context().mapID); self:Refresh()
    end)
    self.summary=label(f,"GameFontNormal",18,-75,960)
    label(f,"GameFontHighlightSmall",18,-110,80):SetText("Nome ou ID:")
    local search=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
    search:SetSize(260,24); search:SetPoint("TOPLEFT",100,-103); search:SetAutoFocus(false)
    search:SetScript("OnTextChanged",function(box) self.view.search=box:GetText(); self.page=1; self:Render() end)
    search:SetScript("OnEscapePressed",function(box) box:ClearFocus() end); self.search=search
    self.statusButton=button(f,"Status: Pendentes",380,-103,180,function()
        self.view.status=({pending="all",all="done",done="active",active="pending"})[self.view.status]
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
    self.sidebarTitle=label(f,"GameFontNormal",18,-145,215)
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",16,-169); scroll:SetSize(200,433)
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
            if self.view.tab=="route" and IsShiftKeyDown() then
                local q=b.entry.quest; self.db.quests[q.id]=self.db.quests[q.id] or {}; self.db.quests[q.id].ignored=true
                self:Refresh(); return
            end
            self.selected=b.entry; self:ShowDetails(b.entry)
        end)
        row:SetScript("OnEnter",function(b)
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
    button(f,"< Anterior",254,-443,105,function() self.page=math.max(1,self.page-1); self.selected=nil; self:Render() end)
    self.pageText=label(f,"GameFontHighlightSmall",379,-450,385)
    button(f,"Proxima >",868,-443,110,function() self.page=math.min(self.pages or 1,self.page+1); self.selected=nil; self:Render() end)
    self.detailTitle=label(f,"GameFontNormal",254,-485,725)
    self.detailTitle:SetMaxLines(1)
    -- Scrollable details keep long prerequisite chains accessible.
    local detailScroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT",254,-510); detailScroll:SetSize(700,94)
    local detailContent=CreateFrame("Frame",nil,detailScroll); detailContent:SetSize(690,96)
    detailScroll:SetScrollChild(detailContent); self.detailContent=detailContent
    self.detailBody=label(detailContent,"GameFontHighlightSmall",0,0,680)
    self.giverButton=button(f,"Marcar coleta",254,-614,150,function()
        if self.selected and self.selected.point then self:Navigate(self.selected.point) end
    end)
    self.entranceButton=button(f,"Entrada dungeon",414,-614,160,function()
        local point=self.selected and self.Catalog:Entrance(self.selected.dungeon)
        if point then self:Navigate(point) end
    end)
    self.trackButton=button(f,"Rastrear quest",584,-614,150,function()
        local q=self.selected and self.selected.quest
        if q and self.Catalog.logs and self.Catalog.logs[q.id] then
            self:Call(C_QuestLog,"AddQuestWatch",q.id); self:Call(C_SuperTrack,"SetSuperTrackedQuestID",q.id)
            self:Print("Quest rastreada: " .. q.title)
        end
    end)
    self.previousButton=button(f,"Ver pre-requisito",744,-614,235,function()
        local record=self.selected and self.Catalog.byID[self.selected.quest.id]
        local id=record and self.Catalog:FirstMissing(record)
        if id and self.Catalog.byID[id] then
            self.view.tab="history"; self.view.status="all"; self.view.levelOnly=false
            self.view.dungeonID=nil; self.selected=nil; self.page=1
            self.search:SetText(tostring(id)); self.view.search=tostring(id); self:Render()
        end
    end)
    self.footer=label(f,"GameFontDisableSmall",18,-654,960)
    f:SetScript("OnShow",function() if self.ready then self:Refresh() end end); f:Hide()
end
function A:ShowDetails(entry)
    if not entry then
        self.detailTitle:SetText("Selecione uma quest para planejar o proximo passo")
        self.detailBody:SetText("Veja onde aceitar, quais pre-requisitos faltam e marque a entrada da dungeon.")
        self.giverButton:SetEnabled(false); self.entranceButton:SetEnabled(false); self.trackButton:SetEnabled(false)
        self.previousButton:SetEnabled(false); return
    end
    local q=entry.quest; local record=self.Catalog.byID[q.id]
    self.detailTitle:SetText(q.title .. "  |  #" .. q.id)
    local pieces={entry.reason or ""}
    if record then
        local requirements=self.Catalog:Requirements(record,self.context.level)
        if #requirements>0 then pieces[#pieces+1]="PRE-REQUISITOS\n" .. table.concat(requirements,"\n") end
        local origin,point=self.Catalog:Location(record,entry.state=="turnin"); entry.point=point
        pieces[#pieces+1]=(entry.state=="turnin" and "Entregar: " or "Aceitar: ") .. origin
        if record.dungeonSource then pieces[#pieces+1]="Vinculo com a dungeon: " .. record.dungeonSource end
    else entry.point=q; pieces[#pieces+1]="Coordenadas do proximo objetivo fornecidas pelo jogo." end
    self.detailBody:SetText(table.concat(pieces,"\n"))
    self.detailContent:SetHeight(math.max(96,self.detailBody:GetStringHeight()+8))
    self.giverButton:SetText(entry.state=="turnin" and "Marcar entrega" or (q.accepted and "Marcar objetivo" or "Marcar coleta"))
    if q.accepted and q.x and q.y then entry.point=q end
    self.giverButton:SetEnabled(entry.point and entry.point.mapID and true or false)
    self.entranceButton:SetEnabled(self.Catalog:Entrance(entry.dungeon)~=nil)
    self.trackButton:SetEnabled(self.Catalog.logs and self.Catalog.logs[q.id]~=nil or false)
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
    local view=self.view; local routeMode=view.tab=="route"; local areaMode=view.tab=="area"
    self.levelCheck:SetShown(not routeMode and not areaMode); self.charCheck:SetShown(not routeMode and not areaMode)
    self.areaDungeonCheck:SetShown(areaMode); self.areaRepeatCheck:SetShown(areaMode)
    self.areaDungeonCheck:SetChecked(view.areaDungeons); self.areaRepeatCheck:SetChecked(view.areaRepeatables)
    self.itemCheck:SetShown(routeMode); self.soloCheck:SetShown(routeMode); self.statusButton:SetShown(not routeMode)
    self.levelCheck:SetChecked(view.levelOnly); self.charCheck:SetChecked(view.myCharacter)
    self.itemCheck:SetChecked(self.db.options.avoidItems); self.soloCheck:SetChecked(self.db.options.solo)
    self.statusButton:SetText("Status: " .. ({all="Todas",pending="Pendentes",done="Concluidas",active="Em andamento"})[view.status] .. " >")
    for key,tab in pairs(self.tabs) do tab:SetEnabled(key~=view.tab) end
    local entries,counts={},{done=0,pending=0,active=0,total=0}
    if areaMode then
        entries,counts=self.Catalog:AreaView(self.context,view); self.areaStats=counts
        self.summary:SetText(string.format("%s  |  %d/%d concluidas (%d%%)  |  Faltam %d quests da base",
            self.context.name,counts.done,counts.total,counts.percent,counts.remaining))
        self.listTitle:SetText("Quests da area atual - todos os niveis do seu personagem")
    elseif routeMode then
        local search=string.lower(view.search)
        for _,q in ipairs(self.route or {}) do
            if search=="" or string.find(string.lower(q.title .. " " .. q.id),search,1,true) then
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
    self:RenderSidebar(); self.entries=entries
    self.pages=math.max(1,math.ceil(#entries/PAGE_SIZE)); self.page=math.min(self.page,self.pages)
    self.pageText:SetText(string.format("Pagina %d/%d  |  %d resultados",self.page,self.pages,#entries))
    for i,row in ipairs(self.rows) do
        local entry=entries[(self.page-1)*PAGE_SIZE+i]; row:SetShown(entry~=nil)
        if entry then
            row.entry=entry; local q=entry.quest
            row.title:SetText((routeMode and (((self.page-1)*PAGE_SIZE+i) .. ". ") or "") .. q.title)
            row.status:SetText((colors[entry.state] or "") .. (names[entry.state] or "") .. "|r")
            local subtitle=entry.dungeon and entry.dungeon.name or (entry.reason or "")
            local record=self.Catalog.byID[q.id]
            if record and (entry.state=="locked" or entry.state=="verify") then
                local _,requirements=self.Catalog:Requirements(record,self.context.level)
                subtitle="Requer: " .. requirements
            end
            row.subtitle:SetText(string.format("Nivel %s  |  #%d  |  %s",q.level and q.level>0 and q.level or "?",q.id,subtitle))
        end
    end
    self.empty:SetShown(#entries==0)
    self.empty:SetText(self.Catalog.loading and "Carregando a base de quests..." or
        (not self.Catalog.ready and not routeMode and (self.Catalog.message or "Catalogo indisponivel.") or "Nenhuma quest neste filtro. Tente Status: Todas ou desmarque Meu nivel."))
    local selected
    if self.selected then for _,entry in ipairs(entries) do if entry.quest.id==self.selected.quest.id then selected=entry; break end end end
    self.selected=selected or entries[(self.page-1)*PAGE_SIZE+1]; self:ShowDetails(self.selected)
    self.footer:SetText(self.Catalog.loading and string.format("Indexando QuestieDB: %d/%d",self.Catalog.progress,self.Catalog.total)
        or (self.Catalog.message or "Rota local") .. "  |  Pendente nao garante disponibilidade no servidor.  |  /fqr ajuda")
end
