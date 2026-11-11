local A=TEST_ADDON
local C=A.Catalog
C.completed={[200]=true}; C.character.completed={}
C.logs={[202]={questID=202}}
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("PASS requirements: " .. name) end
test("all blockers include readable quest names and level",function()
 local lines,summary=C:Requirements({requiredLevel=30,preQuestGroup={200,204}},20)
 local full=table.concat(lines,"\n")
 assert(full:find("[FALTA] Nivel 30",1,true))
 assert(full:find("[OK] Concluir: Area quest 200",1,true))
 assert(summary:find("Area quest 204",1,true) and not summary:find("Area quest 200",1,true))
end)
test("OR prerequisites are satisfied by one alternative",function()
 local _,summary=C:Requirements({preQuestSingle={200,204}},20)
 assert(summary=="Requisitos conhecidos atendidos")
 local lines,missing=C:Requirements({preQuestSingle={203,204}},20)
 assert(lines[1]:find(" OU ",1,true) and missing:find("Uma das alternativas",1,true))
end)
test("active prerequisites differ from previously completed quests",function()
 local lines=C:Requirements({preQuestGroup={-200,-202}},20)
 assert(lines[1]:find("[FALTA] Manter ativa",1,true))
 assert(lines[2]:find("[OK] Manter ativa",1,true))
end)
test("special requirements expose concrete values without claiming validation",function()
 local lines,summary=C:Requirements({requiredSkill={164,100},requiredMinRep={76,3000},
    requiredSourceItems={30},requiredSpell=123},20)
 assert(#lines==4 and summary:find("Ferraria: habilidade 100",1,true))
 assert(summary:find("faccao #76, valor 3000",1,true))
 for _,line in ipairs(lines) do assert(line:find("[CONFERIR]",1,true)) end
end)
test("parent requirement remains navigable after OR is satisfied",function()
 assert(C:FirstMissing({preQuestSingle={200},parentQuest=204})==204)
 assert(C:FirstMissing({availableStartingWith=204})==204)
end)
test("locked rows, tooltip and details contain prerequisites",function()
 A.view.search=""; A.view.status="all"; A.context={mapID=10,level=20,name="Teste"}; A:SelectTab("area")
 local row
 for _,candidate in ipairs(A.rows) do
  if candidate.entry and candidate.entry.quest.id==203 then row=candidate; break end
 end
 assert(row and row.subtitle.text:find("Requer: Nivel 40",1,true))
 row.scripts.OnClick(row)
 assert(A.detailBody.text:find("[FALTA] Nivel 40",1,true))
 row.scripts.OnEnter(row)
end)
print("TOTAL " .. passed .. " requirements tests passed")
