# Forever Quest Route

Addon para **WoW Forever**, Interface **16001**. Versão **0.3.1**.

Mostra o progresso de quests na área atual, organiza quests de dungeons, consulta requisitos e histórico por personagem e sugere uma rota local.

## Baixar e instalar

1. Abra [Releases](https://github.com/luckpng/ForeverQuestRoute/releases/latest) e baixe **ForeverQuestRoute-0.3.1.zip**.
2. Extraia a pasta `ForeverQuestRoute` dentro de `Interface/AddOns` do jogo.
3. Confira a estrutura: `Interface/AddOns/ForeverQuestRoute/ForeverQuestRoute.toc`.
4. Instale e ative [QuestieDB](https://github.com/Questie/QuestieDB) para usar o catálogo global (contrato 4). Questie é opcional.
5. Reinicie o cliente na primeira instalação e digite `/fqr`. Para atualizar uma instalação existente, substitua a pasta e use `/reload`.

O ZIP em Releases já contém a pasta correta. O botão **Code → Download ZIP** baixa o repositório completo; nesse caso, copie somente a pasta interna `ForeverQuestRoute` para AddOns.

## Uso

| Comando | Ação |
| --- | --- |
| `/fqr` | Abre ou fecha o painel |
| `/fqr area` | Progresso e quests da zona atual |
| `/fqr dungeons` | Quests organizadas por dungeon |
| `/fqr historico` | Catálogo e histórico |
| `/fqr rota` | Recomendações locais |
| `/fqr ajuda` | Lista de comandos |

Veja [LEIA-ME.txt](ForeverQuestRoute/LEIA-ME.txt) para os filtros, requisitos e comandos completos.

## Compatibilidade e limites

Desenvolvido para o cliente Forever com Interface 16001. As rotas são aproximadas e o catálogo depende dos dados do QuestieDB. Requisitos especiais e disponibilidade no servidor podem exigir conferência dentro do jogo. A interface ainda precisa de validação visual no cliente; os testes automatizados usam APIs simuladas.

## Dados e privacidade

O addon guarda preferências e progresso por personagem nas SavedVariables locais do jogo. O código do addon não implementa telemetria nem envio desses dados para serviços externos. Dados salvos de jogadores e a base QuestieDB não são distribuídos neste repositório.

## Testes

Com Python e `lupa` instalados:

```sh
python -m pip install lupa cbor2
python tests/run_tests.py
```

São 50 testes em Lua 5.1. A verificação opcional com uma instalação separada de QuestieDB pode ser executada com:

```sh
python tests/check_installed_db.py "CAMINHO/Interface/AddOns/QuestieDB"
```
