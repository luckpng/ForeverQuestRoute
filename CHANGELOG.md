# Histórico de versões

## 0.4.1

- Clique no tracker consulta waypoints específicos e marcadores do mapa quando falta o waypoint principal.
- Objetivos pendentes podem usar locais aproximados de criaturas, objetos e fontes de itens do QuestieDB; entregas usam o receptor conhecido.
- Quando não há destino conhecido, o clique abre a quest no diário sem repetir avisos no chat.
- Locais aproximados são identificados nos detalhes; objetivos concluídos e associações ambíguas não geram destinos.

## 0.4.0

- Tracker compacto com objetivos, barras de progresso, paginação, foco, favoritos e posição por personagem.
- Aba Meu diário com todas as quests aceitas, incluindo outras zonas e uso sem QuestieDB.
- Clique para marcar destino, botão direito para abrir a quest correta e Shift+clique para favoritar no tracker.
- Filtros independentes por aba, busca sem acentos e por várias palavras, ordenação e limpeza de filtros.
- Rota prioriza foco, favoritos e quests aceitas, mantendo filtros de nível e grupo.
- Objetivos continuam atualizando durante combate; planejador oculto evita cálculos globais desnecessários.
- Correções de histórico durante troca de personagem, saves incompletos e recuperação da indexação.
- Waypoints respeitam o mapa preferido e preservam locais de entrega conhecidos quando falta waypoint nativo.
- Melhorias de requisitos opcionais e totais de área, sem alterar o denominador ao filtrar.
- Comandos para escala, posição, foco, tracker e quantidade de etapas da rota.
- 101 testes em Lua 5.1 e verificação automática do pacote.

## 0.3.1

- Planejador de quests por área, dungeons, requisitos, histórico e recomendações locais.
