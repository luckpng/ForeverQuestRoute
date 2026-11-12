local _, A = ...
local C = {}
A.Catalog = C
C.records, C.byID, C.dungeons, C.entityZones = {}, {}, {}, {}
C.logs, C.areaMaps = {}, {}
C.progress, C.total = 0, 0

-- Portuguese names remain searchable with an ordinary keyboard. Multiple words
-- are ANDed; punctuation is literal rather than interpreted as a Lua pattern.
function C:SearchText(value)
    local text=tostring(value or "")
    for _,pair in ipairs({{"[ÀÁÂÃÄàáâãä]","a"},{"[ÈÉÊËèéêë]","e"},
        {"[ÌÍÎÏìíîï]","i"},{"[ÒÓÔÕÖòóôõö]","o"},{"[ÙÚÛÜùúûü]","u"},{"[Çç]","c"}}) do
        -- Lua byte classes cannot represent UTF-8 codepoints. Replace each
        -- complete encoded character, preserving unrelated bytes.
        local chars=pair[1]:sub(2,-2)
        for char in chars:gmatch("[\194-\244][\128-\191]+") do text=text:gsub(char,pair[2]) end
    end
    return string.lower(text)
end

function C:SearchMatches(q,search,extra)
    if not search or search=="" or not search:find("%S") then return true end
    local source=(q.title or "") .. " " .. tostring(q.id or "") .. " " .. (extra or "")
    if q.searchSource~=source then q.searchSource=source; q.searchNormalized=self:SearchText(source) end
    if self.searchQuery~=search then self.searchQuery=search; self.searchNormalized=self:SearchText(search) end
    for word in self.searchNormalized:gmatch("%S+") do
        if not q.searchNormalized:find(word,1,true) then return false end
    end
    return true
end

function C:MatchesStatus(state,status,q)
    status=status or "all"
    if status=="all" then return true end
    if status=="pending" then return state~="done" end
    if status=="active" then return state=="active" or state=="turnin" end
    if status=="available" then return state=="pending" end
    if status=="favorites" then
        return A.Tracker and A.Tracker.IsFavorite and A.Tracker:IsFavorite(q.id) or false
    end
    return state==status
end

-- A view is one synchronous calculation. Cache only within that calculation:
-- a subsequent event, character switch or filter operation always starts fresh.
function C:BeginView()
    local enum=self.provider and self.provider.Enum or {}
    local _,_,raceID=UnitRace("player")
    local _,class=UnitClass("player")
    self.viewCache={done={},states={},raceMask=enum.raceMaskById and enum.raceMaskById[raceID],
        classMask=enum.classKeys and enum.classKeys[class]}
end

function C:EndView()
    self.viewCache=nil
end

local function band(a, b)
    -- Masks may use race bits beyond 32 bits in future clients.
    local result, place = 0, 1
    a, b = a or 0, b or 0
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

function C:Read(entity, id, key)
    if not entity or type(entity[key]) ~= "function" then return nil end
    return A:Call(entity, key, id)
end

-- Provider maps can be plain tables or Lua expressions. Decode a private copy.
local function mapping(value)
    if type(value) == "table" then return value end
    if type(value) == "string" then
        local fn = loadstring(value)
        if fn then
            setfenv(fn, {})
            local ok, result = pcall(fn)
            if ok and type(result) == "table" then return result end
        end
    end
    return {}
end

function C:MapForArea(area)
    local map=self.areaMaps[area]
    return type(map)=="number" and map>0 and map or nil
end

local nonDungeons = {[1977]=true,[2159]=true,[2257]=true,[2597]=true,[2677]=true,
    [2717]=true,[2917]=true,[2918]=true,[3277]=true,[3358]=true,[3428]=true,
    [3429]=true,[3456]=true,[3457]=true,[16236]=true}

function C:Start()
    if self.loading or self.ready then return end
    local db = LibQuestieDB
    if not db or not db.Quest or not db.Support or not db.Support.Get then
        self.message = "Ative QuestieDB para carregar o catalogo global. A rota local continua disponivel."
        return
    end
    local compatible = A:Call(db, "RequireContract", 4)
    if not compatible then self.message = "QuestieDB incompativel: atualize a base de dados."; return end
    local zoneData = A:Call(db.Support, "Get", "ZoneDB")
    local zones = zoneData and zoneData.private
    if not zones or type(zones.dungeons) ~= "table" then
        self.message = "QuestieDB sem tabela de dungeons compativel."; return
    end
    -- A retry must not reuse a partially indexed provider or its derived maps.
    self.records,self.byID,self.dungeons,self.entityZones={},{},{},{}
    self.progress,self.total=0,0
    self.provider = db
    self.areaMaps = {}
    for k,v in pairs(mapping(zones.areaIdToUiMapId)) do self.areaMaps[k]=v end
    for k,v in pairs(mapping(zones.areaIdToUiMapIdOverride)) do self.areaMaps[k]=v end
    self.dungeonArea = {}
    for area, row in pairs(zones.dungeons) do
        if not nonDungeons[area] then
            self.dungeons[area] = {id=area, name=A:Call(C_Map,"GetAreaInfo",area) or row[1], entrance=row[4]}
            self.dungeonArea[area]=area
            for _, alias in ipairs(row[2] or {}) do self.dungeonArea[alias]=area end
        end
    end
    local ids = A:Call(db.Quest, "GetAllIds")
    if type(ids) ~= "table" then self.message="QuestieDB nao retornou IDs de quests."; return end
    self.loading, self.total, self.message = true, #ids, "Carregando catalogo..."
    local index = 1
    local function batch()
        if InCombatLockdown() then C_Timer.After(1, batch); return end
        local ok, err = pcall(function()
            for _=1,40 do
                local id = ids[index]
                if not id then break end
                self:AddRecord(id)
                index = index + 1
            end
        end)
        if not ok then
            self.loading=false; self.message="Erro ao ler QuestieDB: " .. tostring(err)
            A:Schedule(); return
        end
        self.progress=index-1
        if index <= #ids then C_Timer.After(.01,batch)
        else
            self.loading,self.ready=false,true
            self.message=string.format("QuestieDB: %d quests indexadas",#self.records)
            A:Schedule()
        end
    end
    C_Timer.After(.01,batch)
end

function C:EntityDungeon(entityName, id)
    local key=entityName .. id
    if self.entityZones[key] ~= nil then return self.entityZones[key] end
    local spawns=self:Read(self.provider[entityName],id,"spawns") or {}
    local areas={}
    for area in pairs(spawns) do areas[#areas+1]=area end
    table.sort(areas)
    for _,area in ipairs(areas) do
        if self.dungeonArea[area] then
            self.entityZones[key]=self.dungeonArea[area]; return self.entityZones[key]
        end
    end
    self.entityZones[key]=false
    return false
end

function C:FindDungeon(q)
    local direct=self.dungeonArea[q.zone]
    if direct then q.dungeonSource="zona da quest"; return direct end
    local objectives=q.rawObjectives
    for _,group in ipairs({{1,"Npc"},{2,"Object"}}) do
        for _,obj in ipairs(objectives[group[1]] or {}) do
            local area=self:EntityDungeon(group[2],obj[1])
            if area then q.dungeonSource="criatura/objeto do objetivo"; return area end
        end
    end
    for _,obj in ipairs(objectives[3] or {}) do
        for _,source in ipairs({{"npcDrops","Npc"},{"objectDrops","Object"}}) do
            for _,id in ipairs(self:Read(self.provider.Item,obj[1],source[1]) or {}) do
                local area=self:EntityDungeon(source[2],id)
                if area then q.dungeonSource="fonte do item do objetivo"; return area end
            end
        end
    end
    -- Givers inside an instance also identify quests with scripted objectives.
    for _,kind in ipairs({{1,"Npc"},{2,"Object"}}) do
        for _,id in ipairs(q.startedBy[kind[1]] or {}) do
            local area=self:EntityDungeon(kind[2],id)
            if area then q.dungeonSource="quest giver dentro da instancia"; return area end
        end
    end
end

function C:AddRecord(id)
    if type(id)~="number" or id<=0 or id~=math.floor(id) or self.byID[id] then return end
    local entity=self.provider.Quest
    local q={id=id}
    for _,key in ipairs({"name","requiredLevel","questLevel","requiredRaces","requiredClasses",
        "preQuestGroup","preQuestSingle","exclusiveTo","requiredSkill","requiredMinRep",
        "requiredMaxRep","requiredSpell","requiredSpecialization","requiredMaxLevel",
        "parentQuest","requiredSourceItems","requiredRanks","availableUntilCompleted",
        "availableStartingWith","disabledByQuest","nextQuestInChain","specialFlags"}) do
        q[key]=self:Read(entity,id,key)
    end
    q.title=q.name or ("Quest #" .. id)
    q.level=q.questLevel
    q.zone=self:Read(entity,id,"zoneOrSort")
    q.startedBy=self:Read(entity,id,"startedBy") or {}
    q.finishedBy=self:Read(entity,id,"finishedBy") or {}
    q.rawObjectives=self:Read(entity,id,"objectives") or {}
    q.dungeonID=self:FindDungeon(q)
    self.records[#self.records+1]=q; self.byID[id]=q
end

function C:MatchesCharacter(q)
    local raceMask,classMask
    if self.viewCache then raceMask,classMask=self.viewCache.raceMask,self.viewCache.classMask
    else
        local enum=self.provider and self.provider.Enum or {}
        local _,_,raceID=UnitRace("player")
        local _,class=UnitClass("player")
        raceMask=enum.raceMaskById and enum.raceMaskById[raceID]
        classMask=enum.classKeys and enum.classKeys[class]
    end
    if q.requiredRaces and q.requiredRaces~=0 and raceMask and band(q.requiredRaces,raceMask)==0 then return false end
    if q.requiredClasses and q.requiredClasses~=0 and classMask and band(q.requiredClasses,classMask)==0 then return false end
    return true
end

function C:SyncCharacter()
    local guid=UnitGUID("player")
    if not guid then
        -- Login/loading transitions must never display another character's data.
        self.character,self.completed=nil,nil
        self.logs={}
        return
    end
    if type(A.db.characters)~="table" then A.db.characters={} end
    if type(A.db.characters[guid])~="table" then A.db.characters[guid]={completed={}} end
    self.character=A.db.characters[guid]
    if type(self.character.completed)~="table" then self.character.completed={} end
    local ids=A:Call(C_QuestLog,"GetAllCompletedQuestIDs")
    self.completed=nil
    if type(ids)=="table" then
        self.completed={}
        for _,id in ipairs(ids) do self.completed[id]=true end
    end
    self.logs={}
    local count=A:Call(C_QuestLog,"GetNumQuestLogEntries") or 0
    for i=1,count do
        local info=A:Call(C_QuestLog,"GetInfo",i)
        if info and not info.isHeader and info.questID then self.logs[info.questID]=info end
    end
end

function C:Done(id)
    if self.character and self.character.completed[id] then return true end
    if self.completed then return self.completed[id] or false end
    local cache=self.viewCache and self.viewCache.done
    if cache and cache[id]~=nil then return cache[id] end
    local done=A:Call(C_QuestLog,"IsQuestFlaggedCompleted",id)
    if cache then cache[id]=done end
    return done
end

function C:RequirementMet(id)
    if id < 0 then return self.logs[-id] ~= nil end
    return self:Done(id)==true
end

function C:FirstMissing(q)
    for _,id in ipairs(q.preQuestGroup or {}) do
        if not self:RequirementMet(id) then return math.abs(id) end
    end
    local alternatives=q.preQuestSingle or {}
    local alternativeMet=false
    for _,id in ipairs(alternatives) do if self:RequirementMet(id) then alternativeMet=true end end
    if alternatives[1] and not alternativeMet then return math.abs(alternatives[1]) end
    if (q.parentQuest or 0)>0 and not self.logs[q.parentQuest] then return q.parentQuest end
    if (q.availableStartingWith or 0)>0 and not (self.logs[q.availableStartingWith] or self:Done(q.availableStartingWith)) then
        return q.availableStartingWith
    end
end

function C:State(q,level)
    local cache=self.viewCache and self.viewCache.states
    local saved=cache and cache[q]
    if saved and saved.level==level then return saved.state,saved.reason end
    local state,reason=self:ComputeState(q,level)
    if cache then cache[q]={level=level,state=state,reason=reason} end
    return state,reason
end

function C:ComputeState(q, level)
    local log=self.logs[q.id]
    if log then
        if A:Call(C_QuestLog,"IsComplete",q.id) then return "turnin","Pronta para entregar" end
        return "active","Em andamento"
    end
    local done=self:Done(q.id)
    if done then return "done","Concluida neste personagem" end
    if done==nil then return "unknown","Conclusao indisponivel neste cliente" end
    if not self:MatchesCharacter(q) then return "restricted","Outra raca/classe" end
    if level < (q.requiredLevel or 1) then return "locked","Requer nivel " .. q.requiredLevel end
    if q.requiredMaxLevel and q.requiredMaxLevel>0 and level>q.requiredMaxLevel then return "locked","Acima do nivel maximo" end
    for _,id in ipairs(q.exclusiveTo or {}) do
        if self:Done(math.abs(id)) or self.logs[math.abs(id)] then return "locked","Alternativa exclusiva: #" .. math.abs(id) end
    end
    if q.nextQuestInChain and q.nextQuestInChain>0 and (self:Done(q.nextQuestInChain) or self.logs[q.nextQuestInChain]) then
        return "locked","Substituida pela continuacao #" .. q.nextQuestInChain
    end
    if (q.availableUntilCompleted or 0)>0 and self:Done(q.availableUntilCompleted) then return "locked","Disponibilidade encerrada" end
    if (q.disabledByQuest or 0)>0 and (self:Done(q.disabledByQuest) or self.logs[q.disabledByQuest]) then return "locked","Bloqueada por outra quest" end
    if (q.availableStartingWith or 0)>0 and not (self:Done(q.availableStartingWith) or self.logs[q.availableStartingWith]) then
        return "locked","Requer iniciar #" .. q.availableStartingWith
    end
    if q.parentQuest and q.parentQuest>0 and not self.logs[q.parentQuest] then return "locked","Requer quest ativa #" .. q.parentQuest end
    for _,id in ipairs(q.preQuestGroup or {}) do
        if not self:RequirementMet(id) then return "locked","Pre-requisito: #" .. math.abs(id) end
    end
    local single=q.preQuestSingle or {}
    if #single>0 then
        local met=false
        for _,id in ipairs(single) do if self:RequirementMet(id) then met=true end end
        if not met then return "locked","Requer uma quest anterior (veja detalhes)" end
    end
    if q.requiredSkill or q.requiredMinRep or q.requiredMaxRep or (q.requiredSpell or 0)>0 or (q.requiredSpecialization or 0)>0
        or #(q.requiredSourceItems or {})>0 or #(q.requiredRanks or {})>0 then
        return "verify","Pendente: verificar profissao/reputacao/item/requisito especial"
    end
    return "pending","Pendente; requisitos conhecidos atendidos"
end

function C:IsGroup(q)
    local tag=A:Call(C_QuestLog,"GetQuestTagInfo",q.id)
    if tag and (tag.tagID==1 or tag.tagID==81 or tag.tagID==62 or tag.tagID==41) then return true end
    for _,obj in ipairs(q.rawObjectives[1] or {}) do
        local rank=self:Read(self.provider.Npc,obj[1],"rank")
        if rank==1 or rank==2 or rank==3 then return true end
    end
    return false
end

function C:Location(q, finish, preferredMap)
    local by=(finish and q.finishedBy or q.startedBy) or {}
    local pieces, point={},nil
    for _,kind in ipairs({{1,"Npc"},{2,"Object"}}) do
        for _,id in ipairs(by[kind[1]] or {}) do
            local entity=self.provider and self.provider[kind[2]]
            local name=self:Read(entity,id,"name") or (kind[2] .. " #" .. id)
            local spawns=self:Read(entity,id,"spawns") or {}
            local areas={}; for area in pairs(spawns) do areas[#areas+1]=area end
            table.sort(areas,function(a,b)
                local ap,bp=self:MapForArea(a)==preferredMap,self:MapForArea(b)==preferredMap
                if preferredMap and ap~=bp then return ap end
                return a<b
            end)
            local place
            for _,area in ipairs(areas) do
                for _,xy in ipairs(spawns[area]) do
                    if type(xy[1])=="number" and type(xy[2])=="number"
                        and xy[1]>=0 and xy[1]<=100 and xy[2]>=0 and xy[2]<=100 then
                        local map=self:MapForArea(area)
                        place=string.format("%s (%.1f, %.1f)",A:Call(C_Map,"GetAreaInfo",area) or ("Area #" .. area),xy[1],xy[2])
                        if map and (not point or preferredMap and map==preferredMap and point.mapID~=preferredMap) then
                            point={mapID=map,x=xy[1]/100,y=xy[2]/100,title=q.title}
                        end
                        break
                    end
                end
                if point and (not preferredMap or point.mapID==preferredMap) then break end
            end
            pieces[#pieces+1]=name .. (place and (" - " .. place) or " (local desconhecido)")
            -- Limit detail text, but continue searching all givers for a point
            -- on the requested map. The first remote giver is not a local pin.
        end
    end
    for _,id in ipairs(by[3] or {}) do
        if #pieces<3 then pieces[#pieces+1]="Item: " .. (self:Read(self.provider and self.provider.Item,id,"name") or ("#" .. id)) end
    end
    while #pieces>3 do table.remove(pieces) end
    return #pieces>0 and table.concat(pieces,"\n") or "Origem nao informada pela base",point
end

-- Use matching unfinished objective groups, never the quest giver, as a
-- fallback for clients without native objective waypoints. Spawns are an
-- approximate destination; scripted/event objectives remain without a pin.
function C:ObjectiveLocation(q,objectives,context)
    if not self.provider then return nil end
    local kinds={monster=1,object=2,item=3}
    local counts,indices={},{}
    for _,objective in ipairs(objectives) do
        if kinds[objective.type] then counts[objective.type]=(counts[objective.type] or 0)+1 end
    end
    local best,bestScore
    local function consider(entityName,id)
        local entity=self.provider[entityName]
        local spawns=self:Read(entity,id,"spawns") or {}
        local areas={}; for area in pairs(spawns) do areas[#areas+1]=area end; table.sort(areas)
        for _,area in ipairs(areas) do
            local map=self:MapForArea(area)
            if map then
                for _,xy in ipairs(spawns[area]) do
                    local x,y=xy[1],xy[2]
                    if type(x)=="number" and type(y)=="number" and x>=0 and x<=100 and y>=0 and y<=100 then
                        local candidate={mapID=map,x=x/100,y=y/100,title=q.title,
                            source="Local aproximado do objetivo (QuestieDB)"}
                        local same=context.mapID==map
                        local distance=same and A.Engine.Distance(context.position,candidate,context.aspect) or nil
                        local score=(same and 0 or 10)+(distance or 0)
                        if not bestScore or score<bestScore then best,bestScore=candidate,score end
                    end
                end
            end
        end
    end
    for _,objective in ipairs(objectives) do
        local kind=kinds[objective.type]
        if kind then
            indices[objective.type]=(indices[objective.type] or 0)+1
            local group=(q.rawObjectives or {})[kind] or {}
            -- Different objective counts cannot be mapped safely by position.
            local raw=counts[objective.type]==#group and group[indices[objective.type]]
            if raw and not objective.finished then
                if kind==1 then consider("Npc",raw[1])
                elseif kind==2 then consider("Object",raw[1])
                else
                    for _,source in ipairs({{"npcDrops","Npc"},{"objectDrops","Object"}}) do
                        for _,id in ipairs(self:Read(self.provider.Item,raw[1],source[1]) or {}) do consider(source[2],id) end
                    end
                end
            end
        end
    end
    return best
end

function C:View(level, filters)
    self:BeginView()
    local rows,counts={}, {done=0,pending=0,active=0,total=0}
    for _,q in ipairs(self.records) do
        local dungeon=q.dungeonID and self.dungeons[q.dungeonID]
        if (filters.tab~="dungeons" or dungeon)
            and (not filters.dungeonID or q.dungeonID==filters.dungeonID)
            and (not filters.myCharacter or self:MatchesCharacter(q))
            and (not filters.favoritesOnly or A.Tracker and A.Tracker:IsFavorite(q.id))
            and (not filters.levelOnly or (q.level or level)>=level-A.db.options.maxBelow
                and (q.level or level)<=level+A.db.options.maxAbove)
            and self:SearchMatches(q,filters.search,dungeon and dungeon.name) then
            local state,reason=self:State(q,level)
            counts.total=counts.total+1
            if state=="done" then counts.done=counts.done+1
            elseif state=="active" or state=="turnin" then counts.active=counts.active+1
            else counts.pending=counts.pending+1 end
            if self:MatchesStatus(state,filters.status,q) then
                rows[#rows+1]={quest=q,state=state,reason=reason,dungeon=dungeon}
            end
        end
    end
    table.sort(rows,function(a,b)
        local da,db=a.dungeon and a.dungeon.name or "",b.dungeon and b.dungeon.name or ""
        if da~=db then return da<db end
        if (a.quest.level or 0)~=(b.quest.level or 0) then return (a.quest.level or 0)<(b.quest.level or 0) end
        return a.quest.id<b.quest.id
    end)
    self:EndView()
    return rows,counts
end

function C:Entrance(dungeon)
    local entry=dungeon and dungeon.entrance and dungeon.entrance[1]
    if not entry or type(entry[2])~="number" or type(entry[3])~="number"
        or entry[2]<0 or entry[2]>100 or entry[3]<0 or entry[3]>100 then return nil end
    local map=self:MapForArea(entry[1])
    if map then return {mapID=map,x=entry[2]/100,y=entry[3]/100,title="Entrada: " .. dungeon.name} end
end

-- Enrich current-map recommendations with unaccepted quests from the global DB.
function C:Recommendations(context, existing)
    if not self.ready then return existing end
    self:BeginView()
    local result,seen={},{}
    for _,q in ipairs(existing) do result[#result+1]=q; seen[q.id]=true end
    for _,q in ipairs(self.records) do
        if not seen[q.id] and not q.dungeonID and self:MatchesCharacter(q)
            and (q.level or context.level)>=context.level-A.db.options.maxBelow
            and (q.level or context.level)<=context.level+A.db.options.maxAbove then
            local state=self:State(q,context.level)
            if state=="pending" then
                local _,point=self:Location(q,false,context.mapID)
                if point and point.mapID==context.mapID then
                    local objectives={}
                    for _,entry in ipairs(q.rawObjectives[1] or {}) do
                        objectives[#objectives+1]={type="monster",numRequired=math.max(1,entry[3] or 1)}
                    end
                    for _,entry in ipairs(q.rawObjectives[3] or {}) do
                        objectives[#objectives+1]={type="item",numRequired=math.max(1,entry[3] or 1)}
                    end
                    local group=self:IsGroup(q)
                    if A.db.quests[q.id] and A.db.quests[q.id].group~=nil then group=A.db.quests[q.id].group end
                    result[#result+1]={id=q.id,title=q.title,level=q.level,mapID=point.mapID,x=point.x,y=point.y,
                        accepted=false,objectives=objectives,group=group,
                        ignored=A.db.quests[q.id] and A.db.quests[q.id].ignored,
                        dropRate=A.db.quests[q.id] and A.db.quests[q.id].dropRate, catalog=true}
                end
            end
        end
    end
    self:EndView()
    return result
end
