local _, A = ...
A.Engine = {}
local E = A.Engine

E.defaults = {avoidItems = true, solo = true, maxAbove = 2, maxBelow = 7, limit = 30,
    preferAccepted = true, trackerVisible = false, trackerLocked = false}

local function finite(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return value
end

local function coord(q)
    return type(q.x) == "number" and type(q.y) == "number"
        and q.x >= 0 and q.x <= 1 and q.y >= 0 and q.y <= 1
end

function E.Distance(a, b, aspect)
    if type(a) ~= "table" or type(b) ~= "table" or not coord(a) or not coord(b) then return nil end
    local dx, dy = (a.x - b.x) * (aspect or 1), a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Effort is a relative heuristic, not an estimate of elapsed minutes or XP/hour.
function E.Effort(q, options)
    local cost, reasons = 1, {}
    local items, kills, other, total, fulfilled = 0, 0, 0, 0, 0
    local known = false
    for _, o in ipairs(q.objectives or {}) do
        known = true
        local required = math.max(0, finite(o.numRequired, 0))
        local done = math.max(0, math.min(required, finite(o.numFulfilled, 0)))
        if o.finished then done = required end
        total, fulfilled = total + required, fulfilled + done
        local remaining = o.finished and 0 or math.max(0, required - done)
        if o.type == "item" then items = items + remaining
        elseif o.type == "monster" then kills = kills + remaining
        else other = other + remaining end
    end
    local drop = finite(q.dropRate)
    if drop and (drop <= 0 or drop > 1) then drop = nil end
    if items > 0 then
        -- Unknown item objectives may be ground pickups OR creature drops.
        local attempts = drop and items / drop or items
        cost = cost + attempts * 0.12 + (options.avoidItems and 2 or 0.4)
        reasons[#reasons + 1] = "itens/coleta"
        reasons[#reasons + 1] = drop and string.format("drop informado: %.0f%%", drop * 100)
            or "drop desconhecido"
    elseif not known and not q.complete then
        cost = cost + 1.5
        reasons[#reasons + 1] = "objetivos desconhecidos"
    end
    cost = cost + kills * 0.07 + other * 0.10
    if kills > 0 then reasons[#reasons + 1] = "combate" end
    if total > 0 then cost = cost * (1 - 0.30 * math.min(1, fulfilled / total)) end
    if q.level and q.level > 0 then
        local delta = q.level - (q.playerLevel or q.level)
        if delta > 0 then cost = cost + delta * 0.65 end
        if delta < -3 then cost = cost + (-delta - 3) * 0.18 end
        reasons[#reasons + 1] = "nivel " .. q.level
    else
        cost = cost + 0.75
        reasons[#reasons + 1] = "nivel desconhecido"
    end
    if q.group then cost = cost + 8; reasons[#reasons + 1] = "grupo/instancia" end
    if q.complete then cost = 0.20; reasons = {"pronta para entregar"} end
    if not coord(q) then cost = cost + 3; reasons[#reasons + 1] = "sem coordenadas" end
    return math.max(0.1, cost), table.concat(reasons, ", ")
end

function E.Build(quests, context, options)
    local settings = {}
    for key,value in pairs(E.defaults) do settings[key] = value end
    for key,value in pairs(options or {}) do settings[key] = value end
    options = settings
    options.maxAbove = math.max(0, finite(options.maxAbove, 2))
    options.maxBelow = math.max(0, finite(options.maxBelow, 7))
    options.limit = math.max(1, math.min(100, math.floor(finite(options.limit, 30))))
    local pool, excluded = {}, 0
    for _, source in ipairs(quests) do
        local q = {}
        for k, v in pairs(source) do q[k] = v end
        q.playerLevel = context.level
        local delta = q.level and q.level > 0 and q.level - context.level or 0
        if q.mapID == context.mapID and not q.finished and not q.ignored
            and (q.complete or (delta <= options.maxAbove and delta >= -options.maxBelow
                and not (options.solo and q.group))) then
            q.effort, q.reason = E.Effort(q, options)
            pool[#pool + 1] = q
        else excluded = excluded + 1 end
    end
    -- Greedy utility routing: low effort + short next leg; nearby objectives
    -- reduce subsequent travel. This is not a global shortest-path solver.
    local route, cursor = {}, context.position or {}
    while #pool > 0 and #route < options.limit do
        local best, bestCost
        for i, q in ipairs(pool) do
            local distance = E.Distance(cursor, q, context.aspect)
            local score = q.effort + (distance and distance * 12 or 4)
            -- Explicit player choices win within eligible quests; no choice bypasses safety filters.
            if q.focused then score = score - 1000
            elseif q.favorite then score = score - 20
            elseif options.preferAccepted and q.accepted then score = score - 2 end
            if not best or score < bestCost or (score == bestCost and q.id < pool[best].id) then
                best, bestCost = i, score
            end
        end
        local q = table.remove(pool, best)
        q.score = bestCost
        q.leg = E.Distance(cursor, q, context.aspect)
        route[#route + 1] = q
        if coord(q) then cursor = q end
    end
    return route, excluded
end
