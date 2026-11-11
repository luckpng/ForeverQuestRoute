local addonName, A = ...
A.route = {}
A.version = "0.4.0"

local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end
local anchors={TOPLEFT=true,TOP=true,TOPRIGHT=true,LEFT=true,CENTER=true,RIGHT=true,
    BOTTOMLEFT=true,BOTTOM=true,BOTTOMRIGHT=true}

-- SavedVariables may come from an older build or a manually edited file.
-- Repair settings in place so character history and unrelated preferences survive.
function A:InitializeDatabase()
    if type(ForeverQuestRouteDB)~="table" then ForeverQuestRouteDB={} end
    self.db=ForeverQuestRouteDB
    if type(self.db.options)~="table" then self.db.options={} end
    if type(self.db.quests)~="table" then self.db.quests={} end
    if type(self.db.characters)~="table" then self.db.characters={} end
    for key,default in pairs(self.Engine.defaults) do
        local value=self.db.options[key]
        if type(value)~=type(default) or type(value)=="number" and not finite(value) then
            self.db.options[key]=default
        end
    end
    local options=self.db.options
    options.maxBelow=math.floor(math.max(0,math.min(80,options.maxBelow)))
    options.maxAbove=math.floor(math.max(0,math.min(80,options.maxAbove)))
    options.limit=math.floor(math.max(1,math.min(100,options.limit)))
    options.uiScale=finite(options.uiScale) and math.max(.75,math.min(1.5,options.uiScale)) or 1
    if type(options.trackerVisible)~="boolean" then options.trackerVisible=false end
    if type(options.trackerLocked)~="boolean" then options.trackerLocked=false end
    for id,settings in pairs(self.db.quests) do
        if type(id)~="number" or not finite(id) or id<=0 or id%1~=0 or type(settings)~="table" then
            self.db.quests[id]=nil
        else
            if settings.dropRate~=nil and (not finite(settings.dropRate) or settings.dropRate<=0 or settings.dropRate>1) then
                settings.dropRate=nil
            end
            if type(settings.ignored)~="boolean" then settings.ignored=nil end
            if type(settings.group)~="boolean" then settings.group=nil end
        end
    end
    local p=self.db.position
    if p and (type(p)~="table" or not anchors[p[1]] or not anchors[p[2]]
        or not finite(p[3]) or not finite(p[4]) or math.abs(p[3])>10000 or math.abs(p[4])>10000) then
        self.db.position=nil
    end
    self.db.schemaVersion=2
end

function A:ApplyUIScale()
    if not self.frame then return end
    local scale=self.db and self.db.options.uiScale or 1
    if UIParent and UIParent.GetWidth and UIParent.GetHeight then
        local w,h=UIParent:GetWidth(),UIParent:GetHeight()
        if finite(w) and finite(h) and w>0 and h>0 then
            scale=math.min(scale,(w-24)/1000,(h-24)/680)
        end
    end
    self.frame:SetScale(math.max(.35,scale))
end

function A:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff62d9b2Forever Quest Route:|r " .. tostring(message))
end

function A:Refresh(forcePlanner)
    if not self.ready or self.refreshing then return end
    if InCombatLockdown() then
        self.dirty = true
        -- Our own objective widgets are unprotected and can reflect read-only
        -- quest progress during combat. Navigation and the planner stay deferred.
        local ok,err=pcall(function()
            if self.RenderTracker then self:RenderTracker() end
            if self.frame:IsShown() and self.view.tab=="tracker" then self:Render() end
        end)
        if not ok then self.lastError=tostring(err) end
        return
    end
    self.refreshing = true
    local ok, err = pcall(function()
        self.context = self:Context()
        self.Catalog:SyncCharacter()
        if self.lastMap ~= self.context.mapID then
            self.lastMap = self.context.mapID
            if self.view.tab=="area" then self.page=1; self.selected=nil end
            self:RequestMap(self.lastMap)
        end
        -- Quest objective events can fire rapidly. A hidden planner needs no
        -- global catalog scan; opening it or requesting /proxima refreshes it.
        if forcePlanner or self.frame:IsShown() then
            self.quests = self:Collect(self.context)
            self.quests = self.Catalog:Recommendations(self.context, self.quests)
            if self.Tracker then
                local focus=self.Tracker:GetFocus()
                for _,q in ipairs(self.quests) do
                    q.favorite=self.Tracker:IsFavorite(q.id)
                    q.focused=focus==q.id
                end
            end
            self.route, self.excluded = self.Engine.Build(self.quests, self.context, self.db.options)
            if self.frame:IsShown() then self:Render() end
        end
        if self.RenderTracker then self:RenderTracker() end
    end)
    self.refreshing = false
    if not ok then
        self.lastError = tostring(err)
        if self.lastError ~= self.reportedError then
            self:Print("Falha ao atualizar: " .. self.lastError)
            self.reportedError = self.lastError
        end
    else self.lastError, self.reportedError = nil, nil end
end

function A:Schedule()
    if not self.ready or self.scheduled then return end
    self.scheduled = true
    C_Timer.After(0.4, function() self.scheduled = false; self:Refresh() end)
end

function A:Command(message)
    local words = {}
    for word in string.gmatch(message or "", "%S+") do words[#words + 1] = word end
    local command = string.lower(words[1] or "")
    if command == "" then self.frame:SetShown(not self.frame:IsShown()); return end
    if command == "dungeons" or command == "historico" or command == "rota" or command == "area" or command=="diario" then
        self:SelectTab(({dungeons="dungeons",historico="history",rota="route",area="area",diario="tracker"})[command])
        self.frame:Show()
        self:Refresh()
    elseif command=="tracker" then
        if self.ToggleTracker then self:ToggleTracker() end
    elseif command=="travar" then
        if self.SetTrackerLocked then self:SetTrackerLocked(not self.db.options.trackerLocked) end
    elseif command=="favorito" or command=="foco" then
        if command=="foco" and words[2]=="limpar" and self.Tracker then
            self.Tracker:SetFocus(nil); self:Refresh(); return
        end
        local id=tonumber(words[2])
        if not finite(id) or id<=0 or id%1~=0 or id>2147483647 then
            self:Print("Uso: /fqr " .. command .. " ID"); return
        end
        if self.Tracker then
            if command=="favorito" then
                local favorite=self.Tracker:ToggleFavorite(id)
                self:Print((favorite and "Favorita: #" or "Favorito removido: #") .. id)
            else self.Tracker:SetFocus(id) end
            self:Refresh()
        end
    elseif command=="escala" then
        local percent=tonumber(words[2])
        if not finite(percent) or percent<75 or percent>150 then
            self:Print("Uso: /fqr escala 100 (75 a 150)"); return
        end
        self.db.options.uiScale=percent/100; self:ApplyUIScale()
    elseif command=="posicao" then
        self.db.position=nil
        self.frame:ClearAllPoints(); self.frame:SetPoint("CENTER"); self:ApplyUIScale()
        if self.ResetTrackerPosition then self:ResetTrackerPosition() end
        self:Print("Posicao dos paineis restaurada.")
    elseif command=="limite" then
        local limit=tonumber(words[2])
        if not finite(limit) or limit<1 or limit>100 or limit%1~=0 then
            self:Print("Uso: /fqr limite 30 (1 a 100 etapas)"); return
        end
        self.db.options.limit=limit; self:Refresh()
    elseif command == "proxima" then
        self:Refresh(true)
        if self.route[1] then self:Navigate(self.route[1]) else self:Print("Nenhuma etapa recomendada.") end
    elseif command == "atualizar" then
        if not self.Catalog.ready and not self.Catalog.loading then self.Catalog:Start() end
        self:RequestMap(self:Context().mapID); self:Refresh()
    elseif command == "nivel" then
        local below, above = tonumber(words[2]), tonumber(words[3])
        if not finite(below) or not finite(above) or below < 0 or above < 0 or below > 80 or above > 80 then
            self:Print("Uso: /fqr nivel 7 2 (ate 7 abaixo e 2 acima)"); return
        end
        self.db.options.maxBelow, self.db.options.maxAbove = math.floor(below), math.floor(above)
        self:Refresh()
    elseif command == "drop" or command == "ignorar" or command == "restaurar" or command == "grupo" then
        local id = tonumber(words[2])
        if not finite(id) or id <= 0 or id ~= math.floor(id) or id>2147483647 then self:Print("Informe o ID numerico da missao."); return end
        local value
        if command == "drop" then
            value = tonumber(words[3])
            if words[3] ~= "limpar" and (not finite(value) or value <= 0 or value > 100) then
                self:Print("Uso: /fqr drop ID 35 (1 a 100%) ou /fqr drop ID limpar"); return
            end
        elseif command == "grupo" and words[3] ~= "sim" and words[3] ~= "nao" and words[3] ~= "limpar" then
            self:Print("Uso: /fqr grupo ID sim|nao|limpar"); return
        end
        self.db.quests[id] = self.db.quests[id] or {}
        local q = self.db.quests[id]
        if command == "drop" then q.dropRate = value and value / 100 or nil
        elseif command == "grupo" then
            if words[3] == "limpar" then q.group = nil else q.group = words[3] == "sim" end
        else q.ignored = command == "ignorar" end
        self:Print("Preferencia salva para #" .. id); self:Refresh()
    elseif command == "diagnostico" then
        local version, build, _, interface = GetBuildInfo()
        self:Print("Addon " .. self.version)
        self:Print(string.format("Cliente %s build %s; Interface %s; mapa %s", tostring(version), tostring(build), tostring(interface), tostring(self.context and self.context.mapID)))
        self:Print("C_QuestLog: " .. tostring(C_QuestLog ~= nil) .. "; C_QuestLine: " .. tostring(C_QuestLine ~= nil))
        self:Print("Catalogo: " .. tostring(self.Catalog.message) .. "; progresso " .. self.Catalog.progress .. "/" .. self.Catalog.total)
        for method, err in pairs(self.apiWarnings) do self:Print(method .. ": " .. err) end
        if self.lastError then self:Print(self.lastError) end
    else
        self:Print("/fqr — painel | /fqr proxima — destino | /fqr atualizar")
        self:Print("/fqr area | /fqr dungeons | /fqr historico | /fqr rota — abre a aba desejada")
        self:Print("/fqr diario — suas quests | /fqr tracker — painel compacto | /fqr travar — mover/travar tracker")
        self:Print("/fqr favorito ID | /fqr foco ID|limpar | /fqr limite 30 | /fqr escala 100 | /fqr posicao")
        self:Print("/fqr nivel 7 2 | /fqr ignorar ID | /fqr restaurar ID")
        self:Print("/fqr drop ID 35 | /fqr drop ID limpar | /fqr grupo ID sim|nao|limpar")
        self:Print("/fqr diagnostico — versao do cliente e falhas de API")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName or A.ready then return end
        A:InitializeDatabase()
        A:CreateUI()
        A:ApplyUIScale()
        if A.CreateTrackerUI then A:CreateTrackerUI() end
        A.ready = true
        A.Catalog:Start()
        SLASH_FOREVERQUESTROUTE1 = "/fqr"
        SlashCmdList.FOREVERQUESTROUTE = function(message) A:Command(message) end
        for _, evt in ipairs({"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
            "QUEST_LOG_UPDATE", "QUEST_DATA_LOAD_RESULT", "QUEST_POI_UPDATE", "QUEST_ACCEPTED",
            "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
            "QUEST_WATCH_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED",
            "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED"}) do
            -- Not every game branch exposes every event.
            pcall(events.RegisterEvent, events, evt)
        end
        A:Print("Carregado. /fqr abre o planejador; /fqr tracker ativa o painel de objetivos.")
        A:Schedule()
    else
        if not A.ready then return end
        if event=="DISPLAY_SIZE_CHANGED" or event=="UI_SCALE_CHANGED" then
            A:ApplyUIScale()
            if A.ApplyTrackerScale then A:ApplyTrackerScale() end
        end
        if event == "PLAYER_REGEN_ENABLED" then A.dirty = false end
        if event == "QUEST_TURNED_IN" and type(name)=="number" then
            A.Catalog:SyncCharacter()
            if A.Catalog.character then A.Catalog.character.completed[name]=true end
        end
        A:Schedule()
    end
end)

-- Recompute position while the panel is visible; never run the scan each frame.
local elapsed = 0
events:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 8 then
        elapsed = 0
        if A.ready and (A.frame:IsShown() or A.db.options.trackerVisible) then A:Schedule() end
    end
end)
