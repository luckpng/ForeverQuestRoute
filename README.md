# Forever Quest Route

Addon para **WoW Forever**, Interface **16001**. Versão **0.4.1**.

Acompanhe objetivos enquanto joga, organize seu diário e planeje o próximo destino. O painel compacto mostra progresso, favoritos e quests em foco; o planejador reúne conclusão por área, dungeons, requisitos e rotas locais.

## Baixar e instalar

1. Abra [Releases](https://github.com/luckpng/ForeverQuestRoute/releases/latest) e baixe **ForeverQuestRoute-0.4.1.zip**.
2. Extraia a pasta `ForeverQuestRoute` dentro de `Interface/AddOns` do jogo.
3. Confira a estrutura: `Interface/AddOns/ForeverQuestRoute/ForeverQuestRoute.toc`.
4. Instale e ative [QuestieDB](https://github.com/Questie/QuestieDB) para usar o catálogo global (contrato 4). Questie é opcional.
5. Reinicie o cliente na primeira instalação e digite `/fqr`. Ative o painel compacto com `/fqr tracker`. Para atualizar uma instalação existente, substitua a pasta e use `/reload`.

O ZIP em Releases já contém a pasta correta. O botão **Code → Download ZIP** baixa o repositório completo; nesse caso, copie somente a pasta interna `ForeverQuestRoute` para AddOns.

## Uso

| Comando | Ação |
| --- | --- |
| `/fqr` | Abre ou fecha o painel |
| `/fqr tracker` | Mostra ou oculta o tracker compacto |
| `/fqr diario` | Quests aceitas em todas as zonas |
| `/fqr area` | Progresso e quests da zona atual |
| `/fqr dungeons` | Quests organizadas por dungeon |
| `/fqr historico` | Catálogo e histórico |
| `/fqr rota` | Recomendações locais |
| `/fqr favorito ID` | Adiciona ou remove um favorito |
| `/fqr foco ID` ou `/fqr foco limpar` | Prioriza uma quest ou limpa o foco |
| `/fqr travar` | Trava ou destrava a posição do tracker |
| `/fqr escala 100` | Ajusta o tamanho do planejador, de 75 a 150% |
| `/fqr posicao` | Restaura a posição dos painéis |
| `/fqr ajuda` | Lista de comandos |

Veja [LEIA-ME.txt](ForeverQuestRoute/LEIA-ME.txt) para os filtros, requisitos e comandos completos.

No tracker, clique para focar e marcar um destino, sem um destino conhecido o clique abre os detalhes; use o botão direito para abrir os detalhes e Shift+clique para alternar um favorito. A roda do mouse percorre as páginas. Favoritos, foco e posição do tracker são separados por personagem.

As abas lembram seus próprios filtros. A busca aceita várias palavras e ignora acentos; a ordenação permite alternar prioridade, status, nível ou nome. **Limpar filtros** restaura apenas a aba atual. Os filtros da área preservam o total de conclusão.

## Compatibilidade e limites

Desenvolvido para o cliente Forever com Interface 16001. Diário e tracker funcionam sem QuestieDB; o catálogo global precisa da base. As rotas são aproximadas. Requisitos especiais e disponibilidade no servidor podem exigir conferência dentro do jogo. Durante combate, o tracker atualiza os objetivos e as ações de navegação/rastreamento ficam indisponíveis em combate. A interface ainda precisa de validação visual no cliente; os testes automatizados usam APIs simuladas.

## Dados e privacidade

O addon guarda preferências e progresso por personagem nas SavedVariables locais do jogo. O código do addon não implementa telemetria nem envio desses dados para serviços externos. Dados salvos de jogadores e a base QuestieDB não são distribuídos neste repositório.

## Testes

Com Python 3.12:

```sh
python -m pip install -r requirements-dev.txt
python tests/run_tests.py
python tests/check_package.py
```

São 107 testes em Lua 5.1, incluindo interface, objetivos durante combate, filtros, navegação, personagens separados e recuperação de preferências. O GitHub Actions repete a suíte em cada alteração. A verificação opcional com uma instalação separada de QuestieDB pode ser executada com:

```sh
python tests/check_installed_db.py "CAMINHO/Interface/AddOns/QuestieDB"
```

Para criar um ZIP de instalação reproduzível, com somente os arquivos do addon:

```sh
python tests/check_package.py --build
```

Veja as mudanças no [histórico de versões](CHANGELOG.md).
