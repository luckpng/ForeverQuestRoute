local _, A = ...
A.apiWarnings = {}

-- Optional calls vary across game branches. Keep failures visible in diagnostics.
function A:Call(namespace, method, ...)
    local fn = namespace and namespace[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    self.apiWarnings[method] = tostring(a)
end

function A:Context()
    local mapID = self:Call(C_Map, "GetBestMapForUnit", "player")
    local pos = mapID and self:Call(C_Map, "GetPlayerMapPosition", mapID, "player")
    local x, y
    if pos and type(pos.GetXY) == "function" then
        local ok, px, py = pcall(pos.GetXY, pos)
        if ok and type(px) == "number" and type(py) == "number"
            and px >= 0 and px <= 1 and py >= 0 and py <= 1 then x, y = px, py end
    end
    local aspect = 1
    local w, h
    if mapID then w, h = self:Call(C_Map, "GetMapWorldSize", mapID) end
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then aspect = w / h end
    local info = mapID and self:Call(C_Map, "GetMapInfo", mapID)
    return {mapID = mapID, level = UnitLevel("player"), position = {x = x, y = y},
        aspect = aspect, name = info and info.name or "Mapa indisponivel"}
end

function A:RequestMap(mapID)
    if not mapID then return end
    self:Call(C_QuestLine, "RequestQuestLinesForMap", mapID)
end

function A:Collect(context)
    local mapID, byID, logs = context.mapID, {}, {}
    if not mapID then return {} end
    local count = self:Call(C_QuestLog, "GetNumQuestLogEntries") or 0
    for i = 1, count do
        local info = self:Call(C_QuestLog, "GetInfo", i)
        if info and not info.isHeader and not info.isHidden and info.questID then
            logs[info.questID] = info
        end
    end
    local function add(id, x, y, title, available)
        if type(id) ~= "number" or id <= 0 then return end
        local existing = byID[id]
        if existing then
            if not existing.x then existing.x, existing.y = x, y end
            return
        end
        local log = logs[id]
        -- Repeatable quests in the log/map remain eligible even if completed before.
        if not log and not available and self:Call(C_QuestLog, "IsQuestFlaggedCompleted", id) then return end
        local q = {id = id, mapID = mapID, x = x, y = y,
            title = (log and log.title) or title or self:Call(C_QuestLog, "GetTitleForQuestID", id),
            accepted = log ~= nil}
        if not q.title or q.title == "" then
            q.title = "Missao #" .. id
            -- One request per ID per session avoids an update event request loop.
            self.dataRequests = self.dataRequests or {}
            if not self.dataRequests[id] then
                self.dataRequests[id] = true
                self:Call(C_QuestLog, "RequestLoadQuestByID", id)
            end
        end
        q.level = (log and (log.difficultyLevel or log.level))
            or self:Call(C_QuestLog, "GetQuestDifficultyLevel", id)
        q.complete = self:Call(C_QuestLog, "IsComplete", id) or false
        q.objectives = self:Call(C_QuestLog, "GetQuestObjectives", id) or {}
        local tag = self:Call(C_QuestLog, "GetQuestTagInfo", id)
        local groupTags = {[1] = true, [41] = true, [62] = true, [81] = true,
            [85] = true, [88] = true, [89] = true, [98] = true}
        q.group = (log and (log.suggestedGroup or 0) > 1)
            or (tag and groupTags[tag.tagID]) or false
        local settings = self.db.quests[id] or {}
        q.ignored, q.dropRate = settings.ignored, settings.dropRate
        q.favorite = self.Tracker and self.Tracker:IsFavorite(id) or false
        q.focused = self.Tracker and self.Tracker:GetFocus() == id or false
        if settings.group ~= nil then q.group = settings.group end
        byID[id] = q
    end
    for _, poi in ipairs(self:Call(C_QuestLog, "GetQuestsOnMap", mapID) or {}) do
        if not poi.isHidden then add(poi.questID, poi.x, poi.y) end
    end
    for id, log in pairs(logs) do
        local targetMap, x, y = self:Call(C_QuestLog, "GetNextWaypoint", id)
        if targetMap == mapID then
            if byID[id] then byID[id].x, byID[id].y = x, y
            else add(id, x, y, log.title) end
        end
    end
    for _, line in ipairs(self:Call(C_QuestLine, "GetAvailableQuestLines", mapID) or {}) do
        if not line.isHidden and (not line.startMapID or line.startMapID == 0 or line.startMapID == mapID) then
            add(line.questID, line.x, line.y, line.questName, true)
        end
    end
    local result = {}
    for _, q in pairs(byID) do result[#result + 1] = q end
    table.sort(result, function(a,b) return a.id < b.id end)
    return result
end

function A:Navigate(q)
    if InCombatLockdown() then self:Print("Marque o destino fora de combate."); return end
    if type(q) ~= "table" or type(q.mapID) ~= "number" or q.mapID <= 0
        or type(q.x) ~= "number" or type(q.y) ~= "number" then
        self:Print("Missao sem coordenadas fornecidas pelo jogo."); return
    end
    local x, y = q.x, q.y
    if x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function" then
        local ok, err = pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(q.mapID, x, y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end)
        if not ok then self:Print("Nao foi possivel marcar: " .. tostring(err)); return end
    elseif TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(q.mapID, x, y, {title = q.title, persistent = false, minimap = true})
    else
        self:Print(string.format("Destino: %s (%.1f, %.1f). Waypoint indisponivel neste cliente.", q.title, x * 100, y * 100))
        return
    end
    self:Print("Destino: " .. q.title)
end
