local _, A = ...
local T = {}
A.Tracker = T

local function number(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return value
end

function T:Store()
    if not A.db then return nil end
    local guid = type(UnitGUID) == "function" and UnitGUID("player")
    if not guid then return nil end
    if type(A.db.characters) ~= "table" then A.db.characters = {} end
    local character = A.db.characters[guid]
    if type(character) ~= "table" then character = {completed={}} end
    A.db.characters[guid] = character
    if type(character.tracker) ~= "table" then character.tracker = {favorites={}} end
    if type(character.tracker.favorites) ~= "table" then character.tracker.favorites = {} end
    if character.tracker.focus ~= nil and (type(character.tracker.focus) ~= "number"
        or character.tracker.focus <= 0 or character.tracker.focus % 1 ~= 0) then character.tracker.focus = nil end
    return character.tracker
end

function T:IsFavorite(id)
    local store = self:Store()
    return store and store.favorites[id] == true or false
end

function T:ToggleFavorite(id)
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return false end
    local store = self:Store()
    if not store then return false end
    store.favorites[id] = not store.favorites[id] or nil
    return store.favorites[id] == true
end

function T:SetFocus(id)
    local store = self:Store()
    if not store or (id ~= nil and (type(id) ~= "number" or id <= 0 or id % 1 ~= 0)) then return false end
    store.focus = id
    return true
end

function T:GetFocus()
    local store = self:Store()
    return store and store.focus
end

-- Every API row is copied: neither Questie nor the game's objective tables are changed.
function T:Objectives(id)
    local raw = A:Call(C_QuestLog, "GetQuestObjectives", id)
    local objectives, required, fulfilled, finished = {}, 0, 0, 0
    for index, row in ipairs(type(raw) == "table" and raw or {}) do
        if type(row) == "table" then
            local need = math.max(0, number(row.numRequired, 0))
            local done = math.max(0, number(row.numFulfilled, 0))
            local complete = row.finished == true or (need > 0 and done >= need)
            if need <= 0 then need = 1; done = complete and 1 or 0 end
            done = complete and need or math.min(need, done)
            required, fulfilled = required + need, fulfilled + done
            if complete then finished = finished + 1 end
            local text = type(row.text) == "string" and row.text or ("Objetivo " .. index)
            objectives[#objectives+1] = {text=text, type=row.type, numRequired=need,
                numFulfilled=done, finished=complete}
        end
    end
    local complete = A:Call(C_QuestLog, "IsComplete", id) == true
    local progress = {required=required, fulfilled=fulfilled, completed=finished,
        total=#objectives, percent=required > 0 and math.floor(fulfilled / required * 100 + .5) or 0,
        known=#objectives > 0, complete=complete}
    if complete then progress.percent = 100; progress.text = "Pronta para entregar"
    elseif #objectives == 0 then progress.text = "Objetivos indisponiveis"
    else progress.text = string.format("%d/%d objetivos  |  %d%%", finished, #objectives, progress.percent) end
    return objectives, progress
end

function T:IsTracked(id)
    return A:Call(C_QuestLog, "GetQuestWatchType", id) ~= nil
end

function T:SetTracked(id, tracked)
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return false, "ID de quest invalido." end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, "Altere o rastreamento fora de combate."
    end
    local method = tracked and "AddQuestWatch" or "RemoveQuestWatch"
    local fn = C_QuestLog and C_QuestLog[method]
    if type(fn) ~= "function" then return false, "Rastreamento nativo indisponivel neste cliente." end
    local ok, result = pcall(fn, id)
    if not ok then A.apiWarnings[method] = tostring(result); return false, "Nao foi possivel alterar o rastreamento." end
    if result == false then return false, "O jogo recusou o rastreamento; confira o limite de quests." end
    return true
end

local function point(map,x,y,title,source)
    map,x,y=number(map),number(x),number(y)
    if not map or map<=0 or map%1~=0 or not x or not y or x<0 or x>1 or y<0 or y>1 then return nil end
    return {mapID=map,x=x,y=y,title=title,source=source}
end

-- Some Forever quests expose a map POI but no global next waypoint.
function T:Destination(id,complete,context)
    context=context or {}
    local title=A:Call(C_QuestLog,"GetTitleForQuestID",id) or ("Quest #" .. id)
    local map,x,y=A:Call(C_QuestLog,"GetNextWaypoint",id)
    local destination=point(map,x,y,title,"Destino do jogo")
    if destination then return destination end
    if context.mapID then
        x,y=A:Call(C_QuestLog,"GetNextWaypointForMap",id,context.mapID)
        destination=point(context.mapID,x,y,title,"Destino do mapa")
        if destination then return destination end
        for _,poi in ipairs(A:Call(C_QuestLog,"GetQuestsOnMap",context.mapID) or {}) do
            if poi.questID==id and not poi.isHidden then
                destination=point(context.mapID,poi.x,poi.y,title,"Marcador do mapa")
                if destination then return destination end
            end
        end
    end
    local record=A.Catalog and A.Catalog.byID[id]
    if complete and record then
        local _,delivery=A.Catalog:Location(record,true,context.mapID)
        if delivery then delivery.source="Entrega conhecida pelo QuestieDB"; return delivery end
    end
end

-- Questie spawn lookup is intentionally on demand, not on every HUD refresh.
function T:ResolveDestination(entry,context)
    if not entry or not entry.quest then return nil end
    local q=entry.quest
    local complete=A:Call(C_QuestLog,"IsComplete",q.id)==true or q.complete
    local destination=self:Destination(q.id,complete,context)
    if destination then destination.title=q.title; return destination end
    if complete then return nil end
    local record=A.Catalog and A.Catalog.byID[q.id]
    if record and A.Catalog.ObjectiveLocation then
        return A.Catalog:ObjectiveLocation(record,q.objectives or {},context or {})
    end
end

-- Unlike the route, the journal keeps accepted quests from every map visible.
function T:Snapshot(context)
    context = context or {}
    local entries, seen = {}, {}
    local count = math.min(1000, math.max(0, number(A:Call(C_QuestLog, "GetNumQuestLogEntries"), 0)))
    local focus = self:GetFocus()
    for i=1,count do
        local log = A:Call(C_QuestLog, "GetInfo", i)
        if type(log) == "table" and not log.isHeader and not log.isHidden
            and type(log.questID) == "number" and log.questID > 0 and not seen[log.questID] then
            local id = log.questID
            seen[id] = true
            local objectives, progress = self:Objectives(id)
            local point=self:Destination(id,progress.complete,context)
            local map=point and point.mapID
            local mapInfo = map and A:Call(C_Map, "GetMapInfo", map)
            local q = {id=id, title=log.title or A:Call(C_QuestLog, "GetTitleForQuestID", id) or ("Quest #" .. id),
                level=log.difficultyLevel or log.level, accepted=true, complete=progress.complete,
                objectives=objectives, mapID=map, x=point and point.x, y=point and point.y,
                favorite=self:IsFavorite(id), focused=focus == id}
            local reason = progress.text
            if type(mapInfo) == "table" and mapInfo.name then reason = reason .. "  |  " .. mapInfo.name end
            local record = A.Catalog and A.Catalog.byID[id]
            entries[#entries+1] = {quest=q, state=progress.complete and "turnin" or "active",
                reason=reason, progress=progress, tracked=self:IsTracked(id), favorite=q.favorite,
                focused=q.focused, point=point, dungeon=record and record.dungeonID and A.Catalog.dungeons[record.dungeonID]}
        end
    end
    table.sort(entries, function(a,b)
        if a.focused ~= b.focused then return a.focused end
        if a.favorite ~= b.favorite then return a.favorite end
        if a.quest.complete ~= b.quest.complete then return a.quest.complete end
        local am = context.mapID ~= nil and a.quest.mapID == context.mapID
        local bm = context.mapID ~= nil and b.quest.mapID == context.mapID
        if am ~= bm then return am end
        if a.tracked ~= b.tracked then return a.tracked end
        return a.quest.id < b.quest.id
    end)
    return entries
end
