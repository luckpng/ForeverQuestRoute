local _, A = ...
local C=A.Catalog

-- Use the quest's geographic category first; class/profession categories fall
-- back to their quest givers. A cross-zone chain is not assigned wholesale.
function C:InMap(q,mapID)
    if not mapID then return false end
    local geographic=q.zone and q.zone>0 and self:MapForArea(q.zone)
    if geographic then return geographic==mapID end
    if not q.originMaps then
        q.originMaps={}
        for _,kind in ipairs({{1,"Npc"},{2,"Object"}}) do
            for _,id in ipairs(q.startedBy[kind[1]] or {}) do
                for area in pairs(self:Read(self.provider[kind[2]],id,"spawns") or {}) do
                    local map=self:MapForArea(area)
                    if map then q.originMaps[map]=true end
                end
            end
        end
    end
    return q.originMaps[mapID]==true
end

function C:AreaExcluded(q,level)
    -- Completed branches still belong to the history. Only unfinished branches
    -- made unavailable by an actual choice/level cap leave the denominator.
    if self:Done(q.id) or self.logs[q.id] then return false end
    for _,id in ipairs(q.exclusiveTo or {}) do
        if self:Done(math.abs(id)) or self.logs[math.abs(id)] then return true end
    end
    if q.requiredMaxLevel and q.requiredMaxLevel>0 and level>q.requiredMaxLevel then return true end
    if (q.availableUntilCompleted or 0)>0 and self:Done(q.availableUntilCompleted) then return true end
    if (q.disabledByQuest or 0)>0 and (self:Done(q.disabledByQuest) or self.logs[q.disabledByQuest]) then return true end
    if q.nextQuestInChain and q.nextQuestInChain>0 and
        (self:Done(q.nextQuestInChain) or self.logs[q.nextQuestInChain]) then return true end
    return false
end

function C:AreaView(context,filters)
    self:BeginView()
    local rows={}
    local stats={total=0,done=0,remaining=0,active=0,turnin=0,locked=0,pending=0,
        verify=0,unknown=0,excluded=0,repeatables=0,dungeons=0,percent=0}
    for _,q in ipairs(self.records) do
        if self:InMap(q,context.mapID) and self:MatchesCharacter(q) then
            local repeatable=(q.specialFlags or 0)%2==1
            local skip=false
            if q.dungeonID and not filters.areaDungeons then
                stats.dungeons=stats.dungeons+1; skip=true
            end
            if repeatable and not filters.areaRepeatables then
                stats.repeatables=stats.repeatables+1; skip=true
            end
            if self:AreaExcluded(q,context.level) then stats.excluded=stats.excluded+1; skip=true end
            if not skip then
                local state,reason=self:State(q,context.level)
                stats.total=stats.total+1
                if state=="done" then stats.done=stats.done+1
                else
                    stats.remaining=stats.remaining+1
                    stats[state]=(stats[state] or 0)+1
                end
                local matches=self:SearchMatches(q,filters.search)
                    and (not filters.favoritesOnly or A.Tracker and A.Tracker:IsFavorite(q.id))
                if matches and self:MatchesStatus(state,filters.status,q) then
                    rows[#rows+1]={quest=q,state=state,reason=reason,
                        dungeon=q.dungeonID and self.dungeons[q.dungeonID]}
                end
            end
        end
    end
    if stats.total>0 then stats.percent=math.floor(stats.done/stats.total*100+.5) end
    local rank={turnin=1,active=2,pending=3,verify=4,locked=5,unknown=6,done=7}
    table.sort(rows,function(a,b)
        local ar,br=rank[a.state] or 8,rank[b.state] or 8
        if ar~=br then return ar<br end
        if (a.quest.level or 0)~=(b.quest.level or 0) then return (a.quest.level or 0)<(b.quest.level or 0) end
        return a.quest.id<b.quest.id
    end)
    self:EndView()
    return rows,stats
end
