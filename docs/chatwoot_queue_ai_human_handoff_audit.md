# Auditoria técnica — filas, Bia e atendimento humano

## 1. Escopo, data e fontes

Esta auditoria é exclusivamente investigativa. Ela não implementa os botões “Enviar para fila” ou “Devolver para a Bia”, não altera comportamento do Chatwoot, não modifica o AntiGravity e não executa operações sobre produção.

Data da análise: 3 de agosto de 2026.

Fontes de verdade examinadas:

- fork `paropeba22/chatwoot`, branch remota `develop`, commit `e28a13169170832162193e1790eb2975b7441cfd`;
- histórico Git das customizações de interface, abas, contadores, SGP, agentes e branding;
- código FOSS e overlays Enterprise do Chatwoot;
- workflow AntiGravity `8k30Q8FFwvr3lbtu`, somente leitura;
- versão ativa e rascunho estável do AntiGravity `4ec83b46-b85c-4413-85cd-c33e7588f9f3`, atualizada em `2026-07-31T20:33:24.693Z`;
- testes existentes e execução focal dos testes de filtros e contadores.

Convenções deste documento:

- **Comprovado**: observado diretamente no código, grafo ou configuração serializada.
- **Inferência**: consequência técnica provável do que foi observado, ainda sem teste integrado em produção.
- **Recomendação**: desenho proposto para uma fase futura.
- **Decisão pendente**: escolha operacional ou de produto que precisa de aprovação.

Dados de clientes, telefones, documentos, tokens, segredos e valores de credentials não foram lidos nem registrados.

## 2. Resumo executivo

### 2.1 Conclusões principais

1. **Comprovado:** as três abas não são estados de domínio. Elas são projeções construídas por uma mistura de filtros do backend, labels e filtros locais do frontend.
2. **Comprovado:** `aguardando-humano` não participa do filtro de nenhuma das três abas. “Em fila” significa hoje “sem `meta.assignee` e sem `bot-bia`”, não “aguardando humano”.
3. **Comprovado:** “Com IA” significa hoje “conversa `open` com label `bot-bia`”, mesmo que exista agente humano atribuído ou `aguardando-humano`.
4. **Comprovado:** a atribuição nativa a `AgentBot` (`assignee_agent_bot_id`) é distinta da label `bot-bia`. A interface usa `meta.assignee` para a lista, enquanto o contador de não atribuídas do backend olha somente `assignee_id`. Isso permite divergência entre lista e contador.
5. **Comprovado:** o handoff do AntiGravity remove `bot-bia`, adiciona `aguardando-humano`, grava atributos e cria nota privada. Ele não altera status, agente humano ou `assignee_agent_bot_id`.
6. **Comprovado:** o AntiGravity para de responder quando a conversa não está `open`, possui qualquer assignee em `meta.assignee` ou contém `aguardando-humano`.
7. **Comprovado:** labels, atribuição, status e custom attributes são atualizados por endpoints separados; labels e custom attributes são substituições do conjunto/hash completo. Encadear esses endpoints no frontend criaria janela de estado parcial e risco de lost update.
8. **Comprovado:** os controllers atuais de assignment e labels autorizam apenas `ConversationPolicy#show?`. Não existe permissão de backend específica para enviar à fila ou devolver à IA.
9. **Recomendação:** implementar cada ação futura como uma transição de domínio única no backend, com `with_lock`, idempotência, validação de estado, política própria, auditoria estruturada e um único resultado autoritativo para o frontend.
10. **Recomendação:** não atribuir a conversa à Bia via `assignee_agent_bot_id` ao “Devolver para a Bia” enquanto o Guard atual rejeitar qualquer `meta.assignee`. No contrato atual, Bia equivale a: conversa aberta, sem assignee, `bot-bia`, sem `aguardando-humano`.
11. **Recomendação:** a Fase 1 pode ser Chatwoot-only. A Fase 2 exige contrato explícito de invalidação de estado com o AntiGravity, pois o n8n é hoje proprietário semântico dos estados financeiro, suporte, cadastro e transferência.
12. **Recomendação:** a futura detecção de inatividade deve viver primariamente em job do Chatwoot/Sidekiq; `updated_at > X` não é critério suficiente.

### 2.2 Bloqueadores antes de implementar

- definir a verdade canônica de ownership entre label, assignee humano e `assignee_agent_bot_id`;
- definir quem pode executar cada transição;
- definir a política de limpeza dos estados do AntiGravity ao devolver para a Bia;
- corrigir ou aceitar conscientemente o comportamento de conversa `resolved` que, com bot ativo, reabre como `pending` e é rejeitada pelo Guard do AntiGravity;
- decidir se a label `aguardando-humano` deve permanecer após um humano assumir;
- validar em ambiente interno o caminho real API Inbox/Evolution para distinguir corretamente mensagens da Bia de mensagens humanas;
- validar a assinatura HMAC dos webhooks no n8n ou comprovar isolamento de rede equivalente.

## 3. Repositório e arquitetura atual

### 3.1 Git e versão

| Item                          | Resultado comprovado                                             |
| ----------------------------- | ---------------------------------------------------------------- |
| Repositório                   | `https://github.com/paropeba22/chatwoot.git`                     |
| Branch padrão e base auditada | `develop`                                                        |
| Commit base auditado          | `e28a13169170832162193e1790eb2975b7441cfd`                       |
| Branch isolada da auditoria   | `agent/chatwoot-queue-ai-audit`                                  |
| Chatwoot declarado            | `4.13.0`                                                         |
| Ruby                          | `3.4.4` no projeto                                               |
| Rails                         | `7.1.5.2`                                                        |
| Node                          | `24.x`                                                           |
| pnpm                          | `10.x`, package manager `10.2.0`                                 |
| Vue                           | `3.5.x`, Composition API coexistindo com componentes Options API |
| Estado local inicial          | limpo, sem divergências não versionadas                          |

O projeto é um fork direto do Chatwoot, não uma camada separada. O merge-base encontrado com o `develop` atual do upstream foi `2ada713f29b2cf5f864cccd3f74d570e73f6b82f`. No momento da auditoria, o fork estava 486 commits atrás e 68 commits à frente desse ponto; o upstream declarava versão `4.16.2`. Isso representa risco elevado de conflitos em upgrades, sobretudo em `ChatList.vue`, sidebar, conversation stores, `Conversation`, `Message` e rotas.

### 3.2 Runtime

| Camada              | Implementação comprovada                                     |
| ------------------- | ------------------------------------------------------------ |
| Backend             | Rails 7.1 / Ruby 3.4                                         |
| Frontend            | Vue 3, Vuex 4, Vue Router, Tailwind/tokens Chatwoot, Vite    |
| Banco               | PostgreSQL; compose de produção usa `pgvector/pgvector:pg16` |
| Cache/fila/realtime | Redis; ActionCable sobre Redis                               |
| Jobs                | Sidekiq 7.3, filas `critical` a `housekeeping`               |
| Web                 | Puma 6.4                                                     |
| Deploy versionado   | Dockerfile, Docker Compose e Procfile                        |
| Deploy externo      | EasyPanel não está descrito no repositório                   |

O `Procfile` executa `db:chatwoot_prepare` no release. Os workflows `publish_foss_docker.yml` e `publish_ee_docker.yml` são acionados por push em `develop`; a branch de auditoria não corresponde a esse gatilho. Conforme confirmação operacional já registrada, o EasyPanel aponta para `develop` e o Auto Deploy está desativado. Nenhum deploy foi executado nesta auditoria.

### 3.3 Principais customizações Grupo Telecom

As customizações relevantes se concentram em quatro grupos:

1. **Workspace/branding:** assets em `public/brand-assets`, temas SCSS, login, layouts, sidebar e nomes amigáveis de inbox.
2. **Operação de conversas:** `ChatList.vue`, tabs, contadores, filtros de rota, cards, cabeçalho, reply box e sidebar de conversa.
3. **SGP:** painel Vue, API cliente, controller account-scoped e integração via n8n.
4. **Central de Incidentes:** feature flag, modelos, serviços, jobs, endpoints e frontend; permanece desabilitada no AntiGravity.

Arquivos core com maior risco de conflito futuro:

- `app/javascript/dashboard/components/ChatList.vue`;
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`;
- `app/javascript/dashboard/store/modules/conversations/*`;
- `app/javascript/dashboard/store/modules/conversationStats.js`;
- `app/models/conversation.rb`;
- `app/models/message.rb`;
- `app/listeners/webhook_listener.rb`;
- `config/routes.rb`;
- `enterprise/app/models/custom_role.rb`.

## 4. Mapa da interface

| Área              | Arquivo/componente                                                             | Estado/store                            | API/eventos                                                | Permissão atual                            | Extensão recomendada                               |
| ----------------- | ------------------------------------------------------------------------------ | --------------------------------------- | ---------------------------------------------------------- | ------------------------------------------ | -------------------------------------------------- |
| Sidebar principal | `components-next/sidebar/Sidebar.vue`                                          | inboxes, labels, teams, custom views    | stores no mount                                            | policy das rotas                           | não colocar as ações aqui                          |
| Lista e abas      | `components/ChatList.vue`                                                      | conversations, stats, pages, filtros    | `GET conversations`, `GET conversations/meta`, ActionCable | acesso à rota/conversas                    | manter como projeção, não executar transição aqui  |
| Tabs              | `components/widgets/ChatTypeTabs.vue`                                          | props do `ChatList`                     | nenhuma direta                                             | herdada                                    | apenas renderizar contadores autoritativos         |
| Itens/lista       | `ConversationList.vue`, `ConversationItem.vue`, cards `components-next`        | conversations                           | store                                                      | herdada                                    | ação de contexto somente numa fase posterior       |
| Cabeçalho         | `components/widgets/conversation/ConversationHeader.vue`                       | conversa selecionada                    | ActionCable/store                                          | herdada                                    | melhor ponto para ação individual                  |
| Resolver/ações    | `components/widgets/conversation/MoreActions.vue`, `buttons/ResolveAction.vue` | conversa selecionada                    | toggle status, mute, transcript                            | sem permissão específica por ação          | adicionar ação state-aware e confirmação no futuro |
| Atribuição/labels | `routes/dashboard/conversation/ConversationAction.vue`                         | conversa, agentes, equipes, labels      | assignments, labels, priority                              | apenas visibilidade da conversa no backend | exibir estado, não orquestrar a nova transição     |
| Banner de tomada  | `ReplyBoxBanner.vue`                                                           | assignee/status                         | toggle status + assignment                                 | herdada                                    | não reutilizar para devolução à Bia                |
| Contadores        | `conversationStats.js` + duas chamadas em `ChatList.vue`                       | mine/unassigned/all + bot counts locais | `/conversations/meta`                                      | finder account/inbox scoped                | substituir por projeções mutuamente exclusivas     |
| Realtime          | `helper/actionCable.js`                                                        | mutations conversations                 | status, updated, assignee, messages                        | token pubsub                               | emitir/consumir um resultado consolidado           |

No desktop, a lista usa larguras próprias do workspace customizado e o painel lateral oferece atribuição/labels. A sidebar principal é redimensionável. Abaixo de 768 px, ela se torna um flyout; por isso, o painel lateral não é um local confiável como única entrada para uma ação operacional. O menu do cabeçalho permanece no contexto da conversa e é a extensão mais consistente entre desktop e mobile.

### 4.1 Melhor local visual futuro

**Recomendação principal:** menu de ações do cabeçalho (`MoreActions.vue`), mostrando apenas uma ação válida para o estado atual e exigindo confirmação.

- “Enviar para fila” quando a conversa está sob a Bia ou sob o agente atual, conforme a política aprovada.
- “Devolver para a Bia” quando a conversa está em atendimento humano/fila e a conta/inbox possui Bia habilitada.

Vantagens: é uma ação sobre a conversa selecionada, já possui contexto, funciona no layout responsivo, reduz cliques acidentais e evita duplicar lógica em lista e painel lateral.

Alternativas:

| Local                     | Vantagem                            | Risco                                                | Parecer                            |
| ------------------------- | ----------------------------------- | ---------------------------------------------------- | ---------------------------------- |
| Botão direto no cabeçalho | alta descoberta e velocidade        | ocupa espaço móvel; clique acidental                 | considerar depois de telemetria    |
| Menu do cabeçalho         | responsivo, contextual, confirmável | um clique adicional                                  | recomendado para V1                |
| Painel lateral            | próximo de assignee/labels          | oculto no mobile e em layouts compactos              | apenas indicador/atalho secundário |
| Menu do item da lista     | operação rápida                     | pouco contexto; maior erro operacional               | fase posterior                     |
| Ação em lote              | ganho operacional                   | concorrência, permissões, rollback e partial failure | não incluir nas Fases 1–2          |

## 5. Funcionamento real das abas

Todas as abas abaixo usam por padrão `status=open` e respeitam os filtros comuns do `ConversationFinder`: conta, inboxes acessíveis, inbox opcional, equipe, labels, tipo de conversa e ordenação. A página possui 25 itens por padrão.

O default de ordenação é `last_activity_at desc`. `view` e `status` são refletidos na query string e parcialmente restaurados de UI settings. Filtros avançados e pastas usam `POST /conversations/filter`; quando um filtro/pasta está ativo, a barra das três tabs é ocultada e a contagem especial da Bia não é aplicada. A sidebar aponta “Todas as conversas” para `view=me`; “Em fila” e “Com IA” existem apenas dentro do `ChatList`.

### 5.1 Meus Atendimentos

- UI: chave `me`.
- Request: `GET /api/v1/accounts/:account_id/conversations?assignee_type=me&status=open...`.
- Backend: `ConversationFinder` aplica `assigned_to(current_user)`, isto é, `assignee_id = usuário atual`.
- Frontend/realtime: `getMineChats` compara `conversation.meta.assignee.id` com o ID do usuário, sem conferir `meta.assignee_type`.
- Não considera labels.
- Não exige `aguardando-humano` ausente.

Risco: em uma atualização inserida apenas pelo frontend, um AgentBot cujo ID numérico colida com o ID do usuário pode ser interpretado como “meu”, pois o getter ignora `assignee_type`. A consulta inicial do backend não sofre essa ambiguidade.

### 5.2 Em fila

- UI: chave `unassigned`.
- Request: `assignee_type=unassigned&status=open`.
- Backend: `Conversation.unassigned`, que verifica somente `assignee_id IS NULL`.
- Frontend: exige `!conversation.meta.assignee` e exclui label `bot-bia`.
- Não exige label `aguardando-humano`.
- Contador mostrado: `unassigned_count` do backend menos `unassigned_count` da consulta com label `bot-bia`.

Consequência: uma conversa sem assignee e sem `bot-bia` entra na fila mesmo sem handoff. Uma conversa atribuída nativamente a AgentBot sem `bot-bia` é contada pelo backend como não atribuída, mas é excluída da lista local porque `meta.assignee` existe.

### 5.3 Com IA

- UI: chave local `bot`; o texto usa a tradução originalmente chamada `all`.
- Request: `assignee_type=all`, `status=open`, `labels[]=bot-bia`.
- Backend: não filtra assignee e exige a label.
- Frontend: usa a lista `all` já filtrada por label.
- Contador: nova consulta `/conversations/meta` com `labels[]=bot-bia` e `assignee_type=all`.
- Não exige assignee vazio.
- Não exclui `aguardando-humano`.

Consequência: uma conversa humana ainda marcada `bot-bia` aparece simultaneamente em “Meus Atendimentos” e “Com IA”. Uma conversa com as duas labels também permanece em “Com IA”.

### 5.4 Tabela de verdade atual

Tabela para `status=open`, sem outros filtros. `H-atual` é o usuário autenticado; `H-outro` é outro agente; `B` é `assignee_agent_bot_id`.

| Assignee real | `bot-bia` | `aguardando-humano` |  Meus | Em fila | Com IA | Observação                                                             |
| ------------- | --------: | ------------------: | ----: | ------: | -----: | ---------------------------------------------------------------------- |
| nenhum        |       não |                 não |   não |     sim |    não | qualquer conversa aberta não classificada vira fila                    |
| nenhum        |       não |                 sim |   não |     sim |    não | estado esperado de handoff atual                                       |
| nenhum        |       sim |                 não |   não |     não |    sim | estado esperado da Bia                                                 |
| nenhum        |       sim |                 sim |   não |     não |    sim | estado contraditório não é rejeitado pela UI                           |
| H-atual       |       não |            qualquer |   sim |     não |    não | atendimento humano atual                                               |
| H-atual       |       sim |            qualquer |   sim |     não |    sim | duplicidade entre abas                                                 |
| H-outro       |       não |            qualquer |   não |     não |    não | aparece em “Meus” do outro agente                                      |
| H-outro       |       sim |            qualquer |   não |     não |    sim | IA e humano podem parecer responsáveis                                 |
| B             |       sim |            qualquer | não\* |     não |    sim | backend ainda conta como `unassigned`; `*` colisão de ID é risco local |
| B             |       não |            qualquer | não\* |     não |    não | contador da fila pode incluir item ausente da lista                    |

Para `pending`, `snoozed` ou `resolved`, a conversa sai das três projeções abertas. O toggle “Conversas Encerradas” muda para `resolved` e força `view=all`; ele não representa mais “encerradas hoje”. O histórico mostra que uma implementação por filtro local em `updated_at` e contador de relatório foi removida no commit `609a85948` por problemas de consistência.

## 6. Labels, atribuição e status

### 6.1 Labels comprovadas

| Label                    | Origem/uso                                                                 | Efeito atual                                           |
| ------------------------ | -------------------------------------------------------------------------- | ------------------------------------------------------ |
| `bot-bia`                | adicionada pelo AntiGravity quando o Guard autoriza; usada pela aba Com IA | exclui da fila local e inclui em Com IA                |
| `aguardando-humano`      | adicionada no handoff do AntiGravity                                       | bloqueia o Guard do n8n; não afeta diretamente as abas |
| `incidente-tecnico-<id>` | preparada pelo backend da Central                                          | Central permanece desligada                            |

Não foi encontrada evidência de labels de financeiro, suporte, comercial ou cancelamento sendo usadas como estado de roteamento no AntiGravity atual. Esses conceitos aparecem como `reason_code`, etapa ou custom attribute. Também não foi encontrado seed/registro versionado que declare `bot-bia` e `aguardando-humano`; `acts_as_taggable_on` pode materializá-las quando a API atualiza labels.

`update_labels` substitui a lista completa. O n8n tenta preservar labels com GET seguido de POST, mas outra alteração entre as duas chamadas pode ser perdida.

Mudanças de label produzem activity message quando há usuário, `conversation.updated`, ActionCable e webhooks. O AntiGravity recebe eventos não `incoming`, mas o primeiro filtro os encerra.

O mesmo `conversation.updated` também pode ser avaliado por Automation Rules do Chatwoot. As regras configuradas na conta são dados runtime e não estão versionadas; antes da Fase 1 será necessário inventariá-las em ambiente seguro para impedir que a nova transição acione uma automação lateral inesperada.

### 6.2 Atribuição

- `assignee_id` representa usuário humano.
- `assignee_agent_bot_id` representa AgentBot.
- `Conversations::AssignmentService` garante exclusão mútua: atribuir humano remove AgentBot; atribuir AgentBot remove humano.
- Unassign humano via `assignee_id: null` não dispara autoassignment por si só, pois o autoassignment depende de mudança de status.
- Abrir uma conversa como agente humano no `toggle_status` atribui automaticamente a conversa ao usuário atual.
- Alterar equipe pode remover o agente se ele não pertence à equipe e pode selecionar outro agente se a equipe permite autoassign.

O frontend atual faz atualização otimista de assignee/equipe antes da confirmação e as actions Vuex engolem erros. Assim, `.then()` pode mostrar sucesso mesmo quando a API falhou. Os novos botões não devem reutilizar esse padrão.

### 6.3 Status

Estados nativos: `open`, `resolved`, `pending`, `snoozed`.

- `pending` é a semântica nativa de conversa sob bot/aguardando cliente; não é fila humana.
- `bot_handoff!` define `waiting_since` se vazio, abre a conversa e dispara evento; não altera labels ou atribuição.
- resolver limpa `waiting_since`.
- mensagem incoming reabre `snoozed` como `open`.
- mensagem incoming em conversa `resolved` com bot ativo muda para `pending`.
- mensagem incoming em API Inbox sem bot ativo reabre como `open`.

**Risco comprovado por composição de regras:** o Guard do AntiGravity exige `open`. Uma conversa resolvida com bot ativo pode reabrir como `pending` e ser ignorada pelo workflow customizado. É necessário teste integrado antes de desenhar a devolução automática.

## 7. Contrato Chatwoot ↔ AntiGravity

### 7.1 Estado do workflow

| Item                           | Valor comprovado em leitura            |
| ------------------------------ | -------------------------------------- |
| Workflow                       | `8k30Q8FFwvr3lbtu`                     |
| Nome                           | AntiGravity                            |
| Ativo                          | sim                                    |
| Rascunho atual                 | `4ec83b46-b85c-4413-85cd-c33e7588f9f3` |
| Versão publicada               | `4ec83b46-b85c-4413-85cd-c33e7588f9f3` |
| Nodes                          | 407                                    |
| Central                        | `technical_incidents_mode=off`         |
| Commit da Central              | `active_commit_enabled=false`          |
| Autorização backend da Central | `backend_active_authorized=false`      |

### 7.2 Entrada

```text
Chatwoot Message/Conversation event
  └─ AgentBotListener
      └─ AgentBots::WebhookJob (fila high)
          └─ POST assinado com X-Chatwoot-Delivery/Timestamp/Signature
              └─ AntiGravity Webhook /webhook-telecom
                  └─ filtro incoming
                  └─ deduplicação PostgreSQL por conversation.id:message.id
                  └─ agregação
                  └─ GET da conversa no Chatwoot
                  └─ Guard_Check
```

`AgentBotListener` envia para o bot atribuído à conversa e também para o bot ativo do inbox. Portanto, atribuir um humano não impede o webhook de ser criado quando existe bot ativo no inbox; o Guard do workflow é a barreira operacional.

O Chatwoot inclui `meta.assignee` e `meta.assignee_type` no payload da conversa. Não existe `conversation.assignee_id` de primeiro nível no presenter auditado. O primeiro `Filtro_Guardiao` do n8n testa esse campo ausente e, por isso, não é a barreira efetiva contra atendimento humano; `Guard_Check`, após GET da conversa, é a barreira correta.

O Webhook do n8n está configurado com `authentication=none`. O Chatwoot gera assinatura HMAC, mas não foi encontrado node de validação dessa assinatura antes da deduplicação. A segurança pode depender de rede/proxy não visível no workflow. Isso deve ser comprovado ou corrigido numa fase própria; não foi alterado aqui.

### 7.3 Guard efetivo

O AntiGravity continua somente se:

- `status == open`;
- não existe `meta.assignee`, `assignee_id` ou `assignee`;
- labels não contêm `aguardando-humano`.

`bot-bia` não é pré-condição. Se ausente e o Guard aprovar, `Chatwoot_Add_BotBia_API` preserva as labels obtidas e adiciona `bot-bia`.

### 7.4 Saída

As respostas da Bia usam nodes EvolutionAPI diretamente. O n8n também usa Chatwoot para:

- ler conversa e mensagens;
- substituir labels;
- substituir/atualizar custom attributes;
- criar notas privadas.

Para mensagens humanas em `Channel::Api`, o Chatwoot cria uma `Message`; `WebhookListener` envia o evento ao `webhook_url` do API Inbox. `SendReplyJob` não implementa transporte WhatsApp para `Channel::Api`: ele mapeia esse canal apenas para `Messages::SendEmailNotificationService`. Portanto, o transporte externo depende do webhook/adaptador do API Inbox, não apenas da criação da Message.

O caminho runtime completo Evolution → callback → Chatwoot não está versionado integralmente neste repositório e não foi testado contra produção nesta auditoria. Deve ser caracterizado numa conversa interna na Fase 5.

### 7.5 Deduplicação

O caminho atual é:

```text
Webhook
  → Filtro_Guardiao
  → Dedup_Prepare_Key_V4
  → Switch_Dedup_Input_Valid_V4
      ├─ inválido → Dedup_FailClosed_V4 → fim
      └─ válido → Postgres_Dedup_Acquire_V4
          ├─ erro → Dedup_FailClosed_V4 → fim
          └─ retorno → Dedup_Acquired_Gate_V4
              ├─ duplicata → fim
              └─ adquirido → agregação/Router
```

A chave é `conversation.id:message.id`, namespace `antigravity:incoming:v3`, TTL de 7 dias, em store PostgreSQL compartilhado. Nenhum payload de cliente é armazenado. Essa deduplicação não deve ser apagada por transições manuais.

## 8. Handoff atual

### 8.1 Pipeline comum

Vinte e quatro origens observadas convergem para:

```text
Set_<motivo>_Handoff
  → Handoff_Get_Labels
  → Handoff_Update_Labels
       remove bot-bia
       preserva demais labels observadas
       adiciona aguardando-humano
  → Chatwoot_Marcar_Retorno_Humano_V2
  → Code_Normalize_Handoff_Note
  → Handoff_Create_Note (private=true)
```

### 8.2 Matriz resumida

| Família              | Motivos comprovados                                                                        | Mensagem anterior ao handoff       | Estado especial                  |
| -------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------- | -------------------------------- |
| Cadastro/liberação   | cadastro, liberação recusada, comprovante                                                  | varia por rota                     | padrão                           |
| Humano/segurança     | cliente irritado, atendimento solicitado, Flávio, router failsafe, AI fallback             | algumas rotas enviam aviso         | padrão                           |
| Cancelamento         | solicitação/status/devolução/troca/disputa/ambiguidade                                     | varia                              | pausa/encerra estados conhecidos |
| Financeiro           | erro, CPF não encontrado, contrato inativo, sem faturas, prazo, pagar todas                | várias rotas enviam resposta antes | padrão, salvo cancelamento       |
| Suporte              | chamado, CPF não encontrado, problema grave, limite CPF, visita técnica, IPTV, ação manual | várias rotas enviam resposta antes | padrão                           |
| Transferência/coleta | endereço, coleta domiciliar                                                                | varia                              | padrão                           |

Estado final comum comprovado:

- `bot-bia` removida;
- `aguardando-humano` adicionada;
- `bia_retorno_humano_pendente=true`;
- nota privada criada;
- status não é alterado;
- assignee humano não é alterado;
- `assignee_agent_bot_id` não é alterado.

Somente handoffs classificados como cancelamento alteram adicionalmente estados existentes: marcam financeiro/suporte/cadastro/transferência como handoff/pausado e definem `liberacao_ativa=false`. Nos demais handoffs, esses estados são preservados.

### 8.3 Riscos do handoff atual

- GET + POST de labels não é atômico e pode perder uma label concorrente.
- Atualização de labels, custom attributes e nota são três operações independentes; falha intermediária deixa estado parcial.
- Não existe idempotency key compartilhada para o handoff como conjunto.
- A nota pode duplicar em retry.
- O n8n não remove assignee; atualmente isso funciona porque o Guard só iniciou em conversa sem assignee, mas não cobre uma futura ação manual.
- Há rotas que enviam mensagem pela Evolution antes de concluir o handoff; uma falha posterior pode deixar cliente avisado sem fila consistente.

## 9. Estados de automação: preservar, pausar ou invalidar

Custom attributes comprovados como relevantes:

- `financeiro_state`;
- `cadastro_state`;
- `suporte_state`;
- `transferencia_state`;
- `liberacao_ativa`;
- `bia_apresentada` e metadados de apresentação;
- `bia_retorno_humano_pendente`;
- contexto transitório de mídia;
- estados internos de seleção/tentativas dentro dos objetos acima.

Os endpoints atuais substituem o hash completo de `custom_attributes`. O n8n faz read-modify-write, sem compare-and-swap. Uma transição futura não deve gravar uma cópia antiga do hash.

### 9.1 Política recomendada

| Evento            | Preservar                                                                        | Pausar/invalidar                                                                                                 | Observação                               |
| ----------------- | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| Enviar para fila  | histórico e estados de negócio para contexto humano; `bia_apresentada`; dedup    | marcar automação pausada e retorno humano pendente                                                               | não apagar evidência útil ao agente      |
| Humano assumir    | estados de negócio; histórico                                                    | remover `aguardando-humano` se a label significar estritamente espera; IA segue bloqueada pelo assignee          | decisão operacional pendente             |
| Devolver para Bia | `bia_apresentada`; referências validadas explicitamente seguras e ainda vigentes | handoff flags, pending question, contadores de tentativa, ações pendentes, `liberacao_ativa`, seleções expiradas | precisa contrato versionado com n8n      |
| Resolver          | histórico/auditoria                                                              | marcar sessão de automação encerrada                                                                             | hoje custom attributes permanecem        |
| Nova mensagem     | dedup existente; contexto válido                                                 | expirar contexto incompatível/mudança de assunto                                                                 | não inferir só por tempo                 |
| Reabrir           | histórico                                                                        | criar nova geração de automação                                                                                  | não reutilizar cegamente sessão anterior |

**Recomendação:** introduzir futuramente um atributo pequeno e versionado, por exemplo `bia_session`, contendo geração, estado (`active`, `paused_human`, `closed`), motivo e timestamp. O n8n deve rejeitar gravações de geração antiga. Isso é mais seguro que o Chatwoot conhecer e reescrever cada schema interno do financeiro/suporte.

## 10. Realtime e contadores

### 10.1 Caminho atual

O backend emite `conversation.created`, `conversation.status_changed`, `conversation.updated`, `assignee.changed` e `message.created` via ActionCable. O frontend atualiza a conversa no Vuex e solicita novos contadores em created/status/updated/assignee.

Após desconexão, o serviço de reconexão busca conversas atualizadas desde a queda. A mutation ignora eventos com `updated_at` mais antigo que o item em memória. Isso reduz regressão por evento fora de ordem, mas não protege as chamadas HTTP de lista/meta contra respostas de requests anteriores.

Para cada atualização de contadores, `ChatList` faz:

- uma chamada debounced ao meta padrão;
- duas chamadas imediatas ao meta de `bot-bia`: `all` e `unassigned`.

### 10.2 Problemas presentes

1. **Alto — projeções não exclusivas:** labels e assignee podem colocar a mesma conversa em Meus e Com IA.
2. **Alto — contador/lista divergem com AgentBot nativo:** backend `unassigned` ignora `assignee_agent_bot_id`; frontend não.
3. **Médio — race de contadores:** as duas chamadas de bot não têm generation/request cancellation; resposta antiga pode sobrescrever a nova.
4. **Médio — zero enganoso:** falha nas chamadas de bot redefine ambos os contadores para zero.
5. **Médio — loading infinito ainda possível:** `fetchAllConversations` e `fetchFilteredConversations` ligam loading, mas seus `catch` não o desligam.
6. **Médio — resposta de aba antiga:** a lista usa store compartilhada; troca rápida de aba não cancela o request anterior.
7. **Médio — tempestade de refresh:** uma transição feita com várias saves pode emitir updated, status e assignee, cada qual disparando três consultas de meta.
8. **Baixo — estado `all` oculto:** resolved usa internamente `view=all`, mas as tabs renderizadas são `me`, `unassigned`, `bot`.

### 10.3 Problemas históricos

- O crash `count undefined` foi mitigado por lookup defensivo e defaults na mutation.
- A paginação de `bot` foi mapeada para a chave `all`, corrigindo o loading infinito específico.
- O fetch da lista `bot-bia` deixou de sobrescrever stats globais.
- “Em fila” passou a subtrair bot-labelled unassigned.
- “Encerrados Hoje” foi substituído por “Conversas Encerradas”; hoje não há filtro “hoje”.

As correções históricas são reais, mas não eliminam as races e divergências atuais listadas acima.

## 11. Permissões e segurança

### 11.1 Situação atual

- `ConversationPolicy#show?` libera admin ou agente com acesso ao inbox/equipe.
- `AssignmentsController` e `LabelsController` herdam uma autorização `show?`; não há `assign?`, `send_to_queue?` ou `return_to_bia?`.
- Custom Roles Enterprise filtram quais conversas são listadas usando `conversation_manage`, `conversation_unassigned_manage` e `conversation_participating_manage`.
- O frontend não possui autorização específica para as ações futuras.

### 11.2 Permissões recomendadas

Adicionar permissões Enterprise/FOSS compatíveis, por exemplo:

- `conversation_send_to_queue`;
- `conversation_return_to_ai`;
- opcionalmente `conversation_automation_audit`.

Admin deve possuir todas. Política operacional sugerida:

- agente pode enviar a própria conversa para a fila;
- supervisor/admin ou `conversation_manage` pode enviar qualquer conversa acessível;
- devolver à Bia deve ser mais restrito, inicialmente supervisor/admin;
- nenhuma ação em inbox sem Bia ativa;
- conversa resolvida exige uma transição explícita, não reabertura implícita.

### 11.3 Controles obrigatórios no backend futuro

- scoping por `Current.account` e inbox acessível;
- Pundit específico por ação;
- validação de estado dentro do lock;
- `with_lock` sobre a conversa;
- idempotency key única por conta/conversa/ação/request;
- expectativa de `last_message_id` ou geração para evitar decisão sobre estado obsoleto;
- preservação de labels não operacionais;
- allowlist de atributos do bot;
- auditoria do ator, origem, before/after e reason code sem PII;
- CSRF/autenticação normal da API e rate limiting;
- resposta `409 Conflict` para precondição obsoleta;
- nenhuma mensagem pública automática na transição.

## 12. Estratégia futura para conversas inativas

### 12.1 Dados disponíveis

- última mensagem pública e privada;
- `message_type`, `sender_type`, `sender_id`, `created_at`, delivery status;
- `waiting_since`, `last_activity_at`, `first_reply_created_at`;
- status, labels, assignee humano, AgentBot e equipe;
- estados da automação em custom attributes;
- último questionamento/etapa dentro dos estados;
- inbox e canal.

Uma lacuna importante é a autoria confiável das respostas da Bia: como o workflow envia pela EvolutionAPI, deve-se confirmar se o callback cria a mensagem no Chatwoot com `sender_type=AgentBot` ou outro marcador estável. Sem isso, “outgoing” não distingue Bia de humano.

### 12.2 Classificação recomendada

| Classe                                | Condição mínima recomendada                                                                                    |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| A. Cliente sem resposta da Bia        | última pública incoming; nenhuma outgoing posterior; IA ativa; não em handoff; prazo de processamento excedido |
| B. Bia aguardando cliente             | última pública comprovadamente da Bia; pending question/etapa aguardando entrada; delivery aceito              |
| C. Atendimento praticamente concluído | ação financeira/info marcada como entregue; nenhuma pergunta pendente; última outgoing da Bia                  |
| D. Etapa intermediária presa          | estado não terminal; claim/etapa antiga; nenhuma execução ativa; sem handoff                                   |
| E. Handoff aguardando humano          | `aguardando-humano`, sem agente, `open`                                                                        |
| F. Humano atendendo                   | `assignee_id` humano, `open`; excluir da automação                                                             |
| G. Nova mensagem posterior            | incoming com ID/timestamp maior que a última resposta registrada; reavaliar imediatamente                      |

Usar dois relógios distintos:

- tempo desde a última entrada ainda não processada;
- tempo desde a última resposta entregue aguardando o cliente.

Não usar `updated_at`, pois labels, leitura, nota, status e outros eventos também o alteram.

### 12.3 Local de execução

**Recomendação:** job idempotente no backend Chatwoot/Sidekiq, com seleção SQL paginada e lock por conversa. Motivos:

- acesso autoritativo a mensagens, assignee, status e labels;
- mesma transação das futuras ações;
- menor exposição de PII;
- retries, métricas e controle por feature flag;
- evita o n8n reconstruir estado de domínio por polling.

O n8n pode receber candidatos sanitizados para classificação semântica ou observação em shadow, mas não deve ser o autor da transição final. Um serviço separado não se justifica na primeira versão.

## 13. Testes existentes e lacunas

### 13.1 Cobertura existente relevante

Backend:

- `spec/finders/conversation_finder_spec.rb`;
- request specs de conversations, assignments e labels;
- `spec/services/conversations/assignment_service_spec.rb`;
- model specs de Conversation e Message;
- `spec/listeners/agent_bot_listener_spec.rb`;
- policy e permission filter specs FOSS/Enterprise;
- ActionCable/Webhook job specs.

Frontend:

- getters de conversations;
- action helpers da lista;
- actions/mutations de conversation stats;
- ActionCable helper;
- API conversation;
- teste de origem da sidebar/tabs.

Não foram encontrados Playwright, Cypress ou outra suíte E2E versionada para esse fluxo.

### 13.2 Validação executada nesta auditoria

- sintaxe Ruby: 10 arquivos centrais, todos `Syntax OK`;
- Vitest focal: 5 arquivos, 43 testes aprovados;
- os testes foram executados no runtime já instalado da worktree irmã da Central; hashes SHA-256 dos oito arquivos de implementação/teste relevantes são idênticos aos da base auditada;
- tentativa de executar na worktree nova não coletou testes por ausência de `node_modules`; a instalação local foi bloqueada por runtime pnpm disponível (`11.x`) incompatível com o requisito `10.x` e pelo timeout do Corepack;
- RSpec não foi executado localmente porque Bundler/dependências Rails não estão instalados no Windows desta worktree.

Isso não é evidência de teste integrado Chatwoot+n8n nem de produção.

### 13.3 Testes a criar nas fases futuras

Backend:

- transição em cada estado permitido/proibido;
- Pundit por papel e Custom Role;
- isolamento por conta/inbox;
- duas ações simultâneas e lock;
- request duplicado/idempotency;
- conflito com mensagem nova;
- preservação de labels não operacionais;
- não duplicação de nota/auditoria;
- resolved/pending/snoozed;
- autoassignment habilitado/desabilitado;
- falha entre passos e rollback transacional;
- geração obsoleta do n8n.

Frontend:

- ação visível por estado/permissão;
- 403/409/422 e rollback visual;
- loading e clique duplo;
- tabs mutuamente exclusivas;
- counters após eventos fora de ordem;
- reconexão ActionCable;
- mobile, teclado, focus e screen reader.

Integração/E2E:

- fila → humano → Bia;
- nenhuma resposta imediata ao devolver;
- próxima incoming chama o AntiGravity uma vez;
- Bia e humano nunca respondem juntos;
- handoff de todas as famílias;
- conversa resolvida/reaberta;
- API Inbox/Evolution delivery e callback;
- Redis/Sidekiq indisponível;
- n8n indisponível;
- eventos duplicados e concorrentes.

## 14. Histórico Git relevante

| Commit                    | Intenção identificada                                              |
| ------------------------- | ------------------------------------------------------------------ |
| `4e49ecd85`               | refactor inicial do painel Grupo Telecom, IA count e SGP           |
| `45beb5c2a`               | correção de loop infinito/Focus Mode e remoção Captain UI          |
| `1cd1ca223`               | restauração de `useFilter` após crash fatal                        |
| `7d25d128b`               | adoção de `bot-bia` e tentativa de “Encerrados Hoje”               |
| `609a85948`               | correção do loading Com IA e substituição por toggle de encerradas |
| `83849d29b`               | limpeza de conversa ativa na troca e isolamento de stats bot       |
| `cfa4b652d`               | correção do contador Em fila quando Com IA ativa                   |
| `0b9d70714`               | limpeza de UI e filtro bot                                         |
| `f6172d953`               | refresh visual e estabilização parcial de contadores               |
| `dc4cfdf8b`               | limpeza de sidebar e novas chamadas de contagem bot                |
| `4e7f9085b`               | ajustes nas tabs e agentes                                         |
| `54e579fae`               | modernização ampla do workspace                                    |
| `4b0070e51`               | restauração de filtros sobre a lista                               |
| `412a8f0c0`               | preservação de filtros e overlays                                  |
| `aaf08c6e5` / `ddeddf663` | integração e ações SGP no painel                                   |

O histórico demonstra regressões recorrentes em uma área de alta complexidade e reforça a necessidade de extrair projeções e transições para unidades menores e testáveis, em vez de ampliar `ChatList.vue`.

## 15. Arquitetura proposta para as ações futuras

### 15.1 Endpoint

Adicionar recurso account-scoped, por exemplo:

```text
POST /api/v1/accounts/:account_id/conversations/:conversation_id/automation_transitions
```

Payload conceitual:

```json
{
  "action": "send_to_human_queue | return_to_bia",
  "request_id": "uuid",
  "expected_last_message_id": "opaque-or-integer",
  "reason_code": "manual_agent_action"
}
```

O backend deve derivar conta, ator, conversa, inbox, estado atual e labels. O frontend não envia o estado desejado de baixo nível.

Resposta:

- conversation serializada autoritativa;
- transition ID;
- status `accepted`, `duplicate` ou `conflict`;
- reason code;
- projeção de aba resultante.

### 15.2 Serviço de domínio

`Conversations::AutomationTransitionService` deve:

1. abrir transação;
2. obter `with_lock` da conversa e recarregar;
3. reautorizar e validar inbox/status/última mensagem;
4. adquirir idempotência;
5. calcular before/after;
6. atualizar assignee, AgentBot, status e atributos allowlisted;
7. atualizar labels operacionais preservando as demais;
8. gravar auditoria/nota uma vez;
9. commit;
10. emitir evento consolidado após commit.

Não deve chamar n8n ou enviar mensagem pública dentro da transação.

### 15.3 Persistência provável

Recomenda-se uma tabela aditiva `conversation_automation_transitions` para auditoria e idempotência:

- `account_id`, `conversation_id`, `actor_id`;
- `action`, `status`, `reason_code`;
- `request_id` único por conta;
- geração de automação;
- snapshots mínimos e sem conteúdo de mensagem/PII;
- timestamps.

Alternativa sem migration: activity messages e auditoria Enterprise. É mais simples, mas não oferece idempotência estruturada comum às edições FOSS/Enterprise e torna consultas operacionais frágeis. Não é recomendada.

## 16. Plano por fases

### Fase 1 — Enviar para fila

- **Backend:** policy, controller e service atômico; transição `send_to_human_queue`.
- **Estado recomendado:** `open`, sem humano/AgentBot, sem `bot-bia`, com `aguardando-humano`, automação pausada, retorno humano pendente.
- **Frontend:** ação state-aware no menu do cabeçalho; confirmação; loading e erros.
- **Banco:** tabela de transições/idempotência.
- **Realtime:** um evento autoritativo; refetch direcionado dos contadores.
- **n8n:** nenhuma mudança necessária se `aguardando-humano` continuar sendo o Guard.
- **Complexidade:** média-alta.
- **Rollback:** feature flag; dados já transicionados exigem ação inversa explícita, não rollback de migration destrutiva.

### Fase 2 — Devolver para a Bia

- **Backend:** transição `return_to_bia`; validar bot ativo no inbox.
- **Estado recomendado no contrato atual:** `open`, sem assignee humano/AgentBot, `bot-bia`, sem `aguardando-humano`.
- **Custom attributes:** incrementar geração, limpar/invalidar estados efêmeros aprovados, manter apresentação e referência segura.
- **Frontend:** ação restrita e confirmação informando que a Bia só responderá após nova mensagem.
- **n8n:** mudança provavelmente necessária para reconhecer geração e rejeitar state writes obsoletos; se não houver mudança, limpeza precisa usar allowlist rígida e ficará acoplada.
- **Complexidade:** alta.
- **Rollback:** enviar novamente à fila; não tentar reconstruir estado apagado sem snapshot.

### Fase 3 — Realtime e contadores

- extrair definição de projeções de aba para módulo único compartilhável/testável;
- tornar as três projeções mutuamente exclusivas;
- criar endpoint de contagens por ownership ou incluir contadores na resposta da transição;
- cancelar/serializar requests antigos;
- nunca zerar contador por falha transitória;
- garantir `finally` no loading;
- reduzir três chamadas de meta por evento;
- caracterizar reconnect/out-of-order.

Não exige n8n. Complexidade média-alta.

### Fase 4 — Revisão automática de inatividade

- job Sidekiq paginado;
- modelo de policy/decision separado de effects;
- shadow mode sem mutações;
- dois relógios e autoria de mensagem comprovada;
- locks e idempotência;
- métricas e fila de revisão humana.

Pode usar n8n apenas como classificador sanitizado. Complexidade alta.

### Fase 5 — Testes conjuntos Chatwoot + n8n

- ambiente isolado e números internos;
- AgentBot/webhook HMAC;
- API Inbox/Evolution/callback;
- todas as rotas de handoff;
- duplicação, concorrência, reabertura e falhas;
- nenhuma conversa real.

Exige coordenação com n8n, mas nenhuma publicação até aprovação. Complexidade alta.

### Fase 6 — Release e deploy manual

1. branch/PR e CI completos;
2. backup de banco e configuração;
3. deploy expand com feature flag off;
4. migration aditiva;
5. web e Sidekiq compatíveis;
6. smoke do comportamento antigo;
7. habilitação interna por conta/inbox;
8. shadow/telemetria;
9. canary de operadores;
10. expansão ou rollback.

Não apagar labels/atributos antigos no primeiro release.

## 17. Riscos e rollback

| Severidade | Risco                                    | Mitigação futura                                                    |
| ---------- | ---------------------------------------- | ------------------------------------------------------------------- |
| Alto       | humano e IA responsáveis simultaneamente | transição atômica + estado mutuamente exclusivo + Guard backend/n8n |
| Alto       | autorização baseada apenas em `show?`    | policies específicas e Custom Roles                                 |
| Alto       | lost update de labels/custom attributes  | lock e update autoritativo server-side                              |
| Alto       | webhook n8n sem validação HMAC visível   | validar assinatura ou comprovar isolamento de rede                  |
| Alto       | resolved reabre pending e Guard ignora   | contrato/teste explícito de reabertura                              |
| Alto       | fork 486 commits atrás do upstream       | plano de rebase/upgrade separado e testes de caracterização         |
| Médio      | contador diferente da lista              | projeção única no backend e contagem autoritativa                   |
| Médio      | requests fora de ordem                   | geração/cancelamento e resposta consolidada                         |
| Médio      | loading infinito em erro                 | `finally` e estado de erro testado                                  |
| Médio      | autoassignment inesperado                | não reutilizar toggle status; validar inbox no service              |
| Médio      | nota/ação duplicada                      | idempotency e índice único                                          |
| Médio      | estado n8n antigo revivido               | generation/epoch versionado                                         |

Rollback de código deve manter migrations aditivas e a feature desligada. Transições já executadas não são automaticamente reversíveis: mensagens, notas e auditoria permanecem, e labels/assignee devem ser reconciliados por uma ação compensatória controlada. Antes de rollback, pausar scheduler futuro, drenar ou bloquear jobs da feature e consultar transições pendentes.

## 18. Decisões pendentes

1. Agente comum pode devolver à Bia ou somente supervisor/admin?
2. “Enviar para fila” será permitido para conversa de outro agente?
3. Ao humano assumir, `aguardando-humano` é removida ou mantida como origem histórica?
4. Conversa resolvida pode ser devolvida à Bia pela mesma ação ou exige reabertura separada?
5. Quais partes de contrato/documento selecionado podem sobreviver à nova geração da Bia?
6. A empresa aceita uma pequena mudança no AntiGravity na Fase 2 para generation/epoch?
7. A label continuará canônica ou será apenas compatibilidade visual de uma coluna/estado de ownership?
8. Qual SLA distingue “Bia processando” de “Bia presa” por canal?
9. Qual é o marcador runtime comprovado de mensagem enviada pela Bia após callback da Evolution?

## 19. Parecer de arquitetura

A interface atual atende à operação por convenção, mas labels e filtros não oferecem as invariantes necessárias aos novos controles. A implementação segura não deve acrescentar dois botões que chamam APIs existentes em sequência. Ela deve primeiro criar uma transição backend autoritativa e depois tornar a UI uma projeção desse resultado.

A recomendação é iniciar a Fase 1 somente após aprovar as decisões de permissão e ownership. A Fase 2 deve aguardar um contrato de geração de estado com o AntiGravity. A automação de inatividade deve permanecer fora do escopo até as transições manuais e os contadores estarem estabilizados.

## 20. Garantias desta auditoria

- nenhum comportamento funcional foi alterado;
- nenhuma migration foi criada ou executada;
- nenhum deploy, preview deploy ou restart foi feito;
- nenhuma variável, credential, webhook, inbox, Redis, Sidekiq ou banco de produção foi alterado;
- nenhuma conversa, label, assignee, mensagem ou status real foi modificado;
- o AntiGravity foi acessado somente para leitura e permaneceu na versão estável;
- a Central de Incidentes permaneceu desligada;
- o único artefato versionável produzido é este documento de auditoria.
