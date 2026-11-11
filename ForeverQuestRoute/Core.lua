local addonName, A = ...
A.route = {}

function A:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff62d9b2Forever Quest Route:|r " .. tostring(message))
end

function A:Refresh()
    if not self.ready or self.refreshing then return end
    if InCombatLockdown() then self.dirty = true; return end
    self.refreshing = true
    local ok, err = pcall(function()
        self.context = self:Context()
        self.Catalog:SyncCharacter()
        if self.lastMap ~= self.context.mapID then
            self.lastMap = self.context.mapID
            if self.view.tab=="area" then self.page=1; self.selected=nil end
            self:RequestMap(self.lastMap)
        end
        self.quests = self:Collect(self.context)
        self.quests = self.Catalog:Recommendations(self.context, self.quests)
        self.route, self.excluded = self.Engine.Build(self.quests, self.context, self.db.options)
        self:Render()
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
    if command == "dungeons" or command == "historico" or command == "rota" or command == "area" then
        self:SelectTab(({dungeons="dungeons",historico="history",rota="route",area="area"})[command])
        self.frame:Show()
        self:Refresh()
    elseif command == "proxima" then
        self:Refresh()
        if self.route[1] then self:Navigate(self.route[1]) else self:Print("Nenhuma etapa recomendada.") end
    elseif command == "atualizar" then
        self:RequestMap(self:Context().mapID); self:Refresh()
    elseif command == "nivel" then
        local below, above = tonumber(words[2]), tonumber(words[3])
        if not below or not above or below < 0 or above < 0 or below > 80 or above > 80 then
            self:Print("Uso: /fqr nivel 7 2 (ate 7 abaixo e 2 acima)"); return
        end
        self.db.options.maxBelow, self.db.options.maxAbove = math.floor(below), math.floor(above)
        self:Refresh()
    elseif command == "drop" or command == "ignorar" or command == "restaurar" or command == "grupo" then
        local id = tonumber(words[2])
        if not id or id <= 0 or id ~= math.floor(id) then self:Print("Informe o ID numerico da missao."); return end
        local value
        if command == "drop" then
            value = tonumber(words[3])
            if words[3] ~= "limpar" and (not value or value <= 0 or value > 100) then
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
        self:Print(string.format("Cliente %s build %s; Interface %s; mapa %s", tostring(version), tostring(build), tostring(interface), tostring(self.context and self.context.mapID)))
        self:Print("C_QuestLog: " .. tostring(C_QuestLog ~= nil) .. "; C_QuestLine: " .. tostring(C_QuestLine ~= nil))
        self:Print("Catalogo: " .. tostring(self.Catalog.message) .. "; progresso " .. self.Catalog.progress .. "/" .. self.Catalog.total)
        for method, err in pairs(self.apiWarnings) do self:Print(method .. ": " .. err) end
        if self.lastError then self:Print(self.lastError) end
    else
        self:Print("/fqr — painel | /fqr proxima — destino | /fqr atualizar")
        self:Print("/fqr area | /fqr dungeons | /fqr historico | /fqr rota — abre a aba desejada")
        self:Print("/fqr nivel 7 2 | /fqr ignorar ID | /fqr restaurar ID")
        self:Print("/fqr drop ID 35 | /fqr drop ID limpar | /fqr grupo ID sim|nao|limpar")
        self:Print("/fqr diagnostico — versao do cliente e falhas de API")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        ForeverQuestRouteDB = ForeverQuestRouteDB or {}
        A.db = ForeverQuestRouteDB
        A.db.options, A.db.quests = A.db.options or {}, A.db.quests or {}
        for k, v in pairs(A.Engine.defaults) do
            if A.db.options[k] == nil then A.db.options[k] = v end
        end
        A:CreateUI()
        A.ready = true
        A.Catalog:Start()
        SLASH_FOREVERQUESTROUTE1 = "/fqr"
        SlashCmdList.FOREVERQUESTROUTE = function(message) A:Command(message) end
        for _, evt in ipairs({"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
            "QUEST_LOG_UPDATE", "QUEST_DATA_LOAD_RESULT", "QUEST_POI_UPDATE", "QUEST_ACCEPTED",
            "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED"}) do
            -- Not every game branch exposes every event.
            pcall(events.RegisterEvent, events, evt)
        end
        A:Print("Carregado. Digite /fqr para abrir as recomendacoes.")
        A:Schedule()
    else
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
        if A.ready and A.frame:IsShown() then A:Schedule() end
    end
end)
