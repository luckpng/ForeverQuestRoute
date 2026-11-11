local _, A = ...
local C=A.Catalog

function C:QuestLabel(id)
    id=math.abs(id)
    local q=self.byID[id]
    local name=q and q.title or (self.provider and self:Read(self.provider.Quest,id,"name"))
    return (name or "Quest") .. " (#" .. id .. ")"
end

local professions={[164]="Ferraria",[165]="Couraria",[171]="Alquimia",[182]="Herborismo",
    [186]="Mineracao",[197]="Alfaiataria",[202]="Engenharia",[333]="Encantamento",
    [393]="Esfolamento",[185]="Culinaria",[129]="Primeiros Socorros",[356]="Pesca"}

-- Report every known condition, rather than only the first State() blocker.
-- Special conditions remain explicitly unverified; do not invent eligibility.
function C:Requirements(q,level)
    local lines,missing={},{}
    local function add(description,met,unverified)
        local mark=unverified and "[CONFERIR] " or (met and "[OK] " or "[FALTA] ")
        lines[#lines+1]=mark .. description
        if not met then missing[#missing+1]=description end
    end
    if (q.requiredLevel or 0)>0 then add("Nivel " .. q.requiredLevel,level>=q.requiredLevel) end
    if (q.requiredMaxLevel or 0)>0 then add("Nivel maximo " .. q.requiredMaxLevel,level<=q.requiredMaxLevel) end
    if not self:MatchesCharacter(q) then add("Raca/classe compativel",false) end
    for _,id in ipairs(q.preQuestGroup or {}) do
        add((id<0 and "Manter ativa: " or "Concluir: ") .. self:QuestLabel(id),self:RequirementMet(id))
    end
    local alternatives=q.preQuestSingle or {}
    if #alternatives>0 then
        local names,met={},false
        for _,id in ipairs(alternatives) do
            local done=self:RequirementMet(id)
            if done then met=true end
            names[#names+1]=(id<0 and "ativa " or "concluida ") .. self:QuestLabel(id) .. (done and " [OK]" or "")
        end
        add("Uma das alternativas: " .. table.concat(names," OU "),met)
    end
    if (q.parentQuest or 0)>0 then add("Manter ativa: " .. self:QuestLabel(q.parentQuest),self.logs[q.parentQuest]~=nil) end
    if (q.availableStartingWith or 0)>0 then
        add("Iniciar ou concluir: " .. self:QuestLabel(q.availableStartingWith),
            self.logs[q.availableStartingWith]~=nil or self:Done(q.availableStartingWith)==true)
    end
    for _,id in ipairs(q.exclusiveTo or {}) do
        add("Nao escolher a alternativa: " .. self:QuestLabel(id),not (self.logs[math.abs(id)] or self:Done(math.abs(id))))
    end
    if (q.availableUntilCompleted or 0)>0 then
        add("Nao ter concluido: " .. self:QuestLabel(q.availableUntilCompleted),not self:Done(q.availableUntilCompleted))
    end
    if (q.nextQuestInChain or 0)>0 then
        add("Nao ter avancado para: " .. self:QuestLabel(q.nextQuestInChain),
            not (self.logs[q.nextQuestInChain] or self:Done(q.nextQuestInChain)))
    end
    if (q.disabledByQuest or 0)>0 and (self.logs[q.disabledByQuest] or self:Done(q.disabledByQuest)) then
        add("Bloqueio por: " .. self:QuestLabel(q.disabledByQuest),false)
    end
    if q.requiredSkill then
        add((professions[q.requiredSkill[1]] or ("Profissao #" .. q.requiredSkill[1]))
            .. ": habilidade " .. (q.requiredSkill[2] or 0),false,true)
    end
    for _,pair in ipairs({{"requiredMinRep","Reputacao minima"},{"requiredMaxRep","Reputacao maxima"}}) do
        local rep=q[pair[1]]
        if rep then add(pair[2] .. ": faccao #" .. rep[1] .. ", valor " .. rep[2],false,true) end
    end
    for _,pair in ipairs({{"requiredSpell","Habilidade/feitico"},{"requiredSpecialization","Especializacao"}}) do
        if (q[pair[1]] or 0)>0 then add(pair[2] .. " #" .. q[pair[1]],false,true) end
    end
    for _,id in ipairs(q.requiredSourceItems or {}) do
        local name=self.provider and self:Read(self.provider.Item,id,"name")
        add("Item: " .. (name or "") .. " (#" .. id .. ")",false,true)
    end
    if #(q.requiredRanks or {})>0 then
        local ranks={}
        for _,r in ipairs(q.requiredRanks) do
            ranks[#ranks+1]=(professions[r[1]] or ("Profissao #" .. r[1])) .. " " .. (r[2] or 0)
        end
        add("Uma habilidade: " .. table.concat(ranks," OU "),false,true)
    end
    local summary=#missing>0 and table.concat(missing,"; ") or "Requisitos conhecidos atendidos"
    return lines,summary
end
