# Chatwoot: Fase 2 — Devolver para a Bia

## Estado e dependências

Esta fase amplia a infraestrutura transacional da Fase 1 com a ação
`return_to_bia`. O endpoint, o lock pessimista, a auditoria e a chave de
idempotência continuam comuns; a projeção e a autorização são resolvidas por
ação. A branch deve permanecer empilhada sobre
`agent/chatwoot-send-to-human-queue` até o PR da Fase 1 ser integrado.

A feature flag de conta `conversation_return_to_bia` usa a coluna booleana
`accounts.conversation_return_to_bia_enabled`, criada com `default: false` e
`null: false`. A flag é independente de `conversation_send_to_human_queue`.

**Gate de produção:** o código Chatwoot pode ser revisado e mesclado com a
flag desligada, mas a ação não pode ser ativada enquanto o AntiGravity não
revalidar a geração da sessão imediatamente antes de toda gravação ou envio.
A versão ativa auditada não possui essa garantia.

## Contrato HTTP

```http
POST /api/v1/accounts/:account_id/conversations/:conversation_id/automation_transitions
Content-Type: application/json
```

```json
{
  "action": "return_to_bia",
  "idempotency_key": "bia-<uuid>",
  "expected_last_message_id": 123,
  "expected_assignee_id": 456
}
```

`expected_last_message_id` e `expected_assignee_id` são chaves obrigatórias
para esta ação. Seus valores podem ser `null` quando, respectivamente, não há
mensagem ou assignee. Ambos são revalidados dentro do lock. O ID da conversa
é o `display_id` escopado pela conta autenticada.

| HTTP | `status/reason_code` | Significado |
| --- | --- | --- |
| 200 | `accepted/returned_to_bia` | projeção persistida |
| 200 | `duplicate/idempotency_replay` | mesma chave já concluída |
| 200 | `duplicate/already_with_bia` | estado final já estava completo |
| 404 | `feature_disabled` | flag desligada ou recurso invisível |
| 409 | `conflict/stale_last_message` | mensagem mudou depois da confirmação |
| 409 | `conflict/stale_assignee` | assignee mudou depois da confirmação |
| 409 | `conflict/conversation_not_open` | estado não é `open` |
| 409 | `conflict/bia_inbox_incompatible` | conversa não possui vínculo operacional comprovado com a Bia |
| 422 | `invalid_transition/*` | action, chave ou expectativa inválida |

Em `409`, a resposta inclui a conversa autoritativa para a store descartar a
visão obsoleta. Não há atualização otimista.

## Resolver por ação

`Conversations::AutomationTransitions::ActionRegistry` associa cada action a:

- feature flag;
- método de policy;
- projection;
- reason codes;
- texto da nota privada.

O service comum valida request, autoriza, verifica a flag, adquire o lock,
resolve replay, revalida concorrência, aplica a projection e grava auditoria.
Não há cadeia de chamadas independentes a assignment, labels e atributos.

## Projeção final

`Conversations::AutomationTransitions::BiaProjection` produz, na mesma
transação:

| Campo | Valor final |
| --- | --- |
| status | `open` |
| assignee humano | `nil` |
| assignee AgentBot | `nil` |
| `aguardando-humano` | removida |
| `bot-bia` | adicionada |
| outras labels | preservadas |
| `bia_retorno_humano_pendente` | `false` |
| `bia_automation_state` | `active` |
| `bia_session_generation` | geração anterior + 1 |
| `bia_returned_at` | timestamp ISO-8601 |
| `bia_resume_after_message_id` | última mensagem pública existente |
| `bia_context_reset_required` | `true` |
| `waiting_since` | `nil` |

Autoassignment é suspenso somente durante a projection e restaurado em
`ensure`. O save usa callbacks normais. A projection não cria mensagem
pública, não muda contato e não apaga histórico.

São aceitas somente conversas `open` que apresentem um vínculo operacional
com a Bia: label `bot-bia` ou `aguardando-humano`, retorno humano pendente ou
estado de automação já registrado. `resolved`, `pending` e `snoozed` são
rejeitadas. Uma conversa integralmente projetada em `Com IA` retorna sucesso
idempotente sem nota ou auditoria adicional.

## Sessão e contexto

Cada transição manual incrementa `bia_session_generation`:

- `send_to_human_queue` grava `paused_human` e retorno humano pendente;
- `return_to_bia` grava `active`, o limite da mensagem e reset obrigatório.

Os estados legados `financeiro_state`, `suporte_state`, `cadastro_state`,
`transferencia_state`, seleções, documento validado e demais dados de negócio
são preservados para consulta. Eles não são retomados por decisão do
Chatwoot. `bia_context_reset_required=true` exige que a próxima execução crie
contexto transitório novo e reutilize somente campos expressamente seguros.

O payload adicional é pequeno e escalar: strings curtas, booleanos, um inteiro
e um timestamp. Nenhum conteúdo, CPF, telefone ou credential é copiado.

## Ausência de resposta imediata

A transição cria somente uma nota privada:

> Conversa devolvida para a Bia por [usuário]. A automação aguardará uma nova
> mensagem do cliente.

O filtro inicial do AntiGravity ativo aceita apenas mensagem `incoming`; nota
privada, mudança de label e alteração de atributos não iniciam o Router. O
limite `bia_resume_after_message_id` impede conceitualmente o reaproveitamento
da mensagem antiga.

Entretanto, a auditoria read-only da versão ativa
`4ec83b46-b85c-4413-85cd-c33e7588f9f3` comprovou que o late guard atual não
compara `bia_session_generation`: o campo de nonce esperado permanece vazio
nos caminhos de IA. Assim, uma execução iniciada antes da fila pode terminar
depois da devolução. A feature deve continuar desligada até um rascunho do
AntiGravity implementar e validar:

1. captura da geração no início;
2. `active` e message ID posterior ao limite;
3. reconsulta antes de qualquer escrita ou envio;
4. igualdade da geração inicial e atual;
5. reset controlado do contexto transitório.

Nenhuma mudança dessa natureza pode ser publicada junto deste PR.

## Idempotência, concorrência e auditoria

A unicidade permanece em
`account_id + conversation_id + action + idempotency_key`; portanto a mesma
chave pode ser usada por actions diferentes sem colisão. O lock da conversa
serializa ações concorrentes. A última mensagem e o assignee são comparados
com a expectativa enviada pela UI depois do reload implícito do lock.

A nota privada e o registro `ConversationAutomationTransition` são gravados
na transação. O registro guarda snapshots sanitizados: status, presença de
assignees, labels operacionais, estado, geração e flags. Não guarda mensagens,
telefone, CPF ou payload da conversa. Falha intermediária reverte projection,
nota e auditoria.

## Permissão

O backend usa `ConversationPolicy#return_to_bia?`:

- administrador: permitido com acesso normal à conversa;
- agente comum: negado;
- Custom Role/supervisor: permitido somente com
  `conversation_return_to_ai` e acesso à conversa/inbox/equipe conforme a
  policy Enterprise.

Conta e conversa são sempre derivadas do contexto autenticado. A UI não é a
barreira autoritativa.

## Frontend, listas e realtime

`MoreActions.vue` mostra “Devolver para a Bia” somente com flag, permissão,
conversa `open` e estado humano/fila. A confirmação informa que não haverá
resposta imediata. Loading compartilhado bloqueia clique concorrente com as
duas actions.

Após a resposta, a store aplica a conversa autoritativa e reconsulta os
contadores. Em `409`, aplica o estado devolvido e mostra conflito. A mutation
continua rejeitando `updated_at` mais antigo e, em empate, rejeita geração
inferior. O estado final é elegível para `Com IA` e não para `Em fila` ou
`Meus Atendimentos`. A refatoração geral dos contadores permanece na Fase 3.

## Migration

Ordem:

```bash
bundle exec rails db:migrate:up VERSION=20260803000001
bundle exec rails db:migrate:up VERSION=20260804000001
```

Teste de reversibilidade antes de uso operacional:

```bash
bundle exec rails db:migrate:down VERSION=20260804000001
bundle exec rails db:migrate:down VERSION=20260803000001
bundle exec rails db:migrate:up VERSION=20260803000001
bundle exec rails db:migrate:up VERSION=20260804000001
```

A segunda migration adiciona a flag booleana, `expected_assignee_id` e amplia
a check constraint de action. O `down` não deve ser executado depois que
existirem registros `return_to_bia`, pois a constraint antiga não os aceita e
a remoção da coluna perde evidência de concorrência.

## Testes focais

```bash
bundle exec rspec \
  spec/models/conversation_automation_transition_spec.rb \
  spec/policies/conversation_policy_spec.rb \
  spec/enterprise/policies/enterprise/conversation_policy_spec.rb \
  spec/requests/api/v1/accounts/conversation_automation_transitions_spec.rb \
  spec/services/conversations/automation_transition_service_spec.rb \
  spec/services/conversations/automation_transition_service_concurrency_spec.rb \
  spec/services/conversations/automation_transition_service_return_to_bia_spec.rb \
  spec/services/conversations/automation_transition_service_return_to_bia_concurrency_spec.rb

pnpm exec vitest run \
  app/javascript/dashboard/api/specs/inbox/conversation.spec.js \
  app/javascript/dashboard/store/modules/specs/conversations/actions.spec.js \
  app/javascript/dashboard/store/modules/specs/conversations/getters.spec.js \
  app/javascript/dashboard/store/modules/specs/conversations/mutations.spec.js \
  app/javascript/dashboard/components/widgets/conversation/specs/MoreActions.spec.js
```

## Deploy manual e ativação gradual

1. Aprovar PRs e CI Linux; manter ambas as flags desligadas.
2. Publicar primeiro um AntiGravity com o contrato de geração validado em
   rascunho, regressão completa e autorização separada.
3. Fazer backup PostgreSQL e registrar SHAs/imagens.
4. Executar migrations Fase 1 e Fase 2.
5. Subir web/workers compatíveis, ainda com flags desligadas.
6. Validar Chatwoot antigo: mensagens internas, assignment, label, nota,
   resolver/reabrir, ActionCable e contadores.
7. Ativar `conversation_send_to_human_queue` somente na conta interna e
   validar fila.
8. Ativar `conversation_return_to_bia` somente na conta interna.
9. Usar conversa interna: fila → Bia; confirmar zero mensagem imediata; enviar
   uma nova mensagem pública; verificar geração, resposta única e abas.
10. Observar logs Rails, Sidekiq, n8n, PostgreSQL, webhook e Evolution antes de
    expandir.

Ativação:

```ruby
account.enable_features!('conversation_return_to_bia')
```

Kill switch:

```ruby
account.disable_features!('conversation_return_to_bia')
```

## Rollback

1. Desligar imediatamente `conversation_return_to_bia`.
2. Se o contrato n8n causar risco, restaurar a versão anterior do workflow e
   manter a flag Chatwoot desligada.
3. Reverter a imagem Chatwoot para o SHA anterior mantendo as colunas/tabela
   aditivas.
4. Não apagar notas ou auditoria já produzidas.
5. Não executar down depois de uso sem exportar e reconciliar registros
   `return_to_bia`.

Uma transição já concluída não é desfeita automaticamente por rollback de
código; eventual reconciliação deve ser uma operação manual controlada.

## Riscos residuais

- ativação bloqueada até o AntiGravity revalidar geração e reset de contexto;
- contadores globais ainda possuem a dívida registrada para a Fase 3;
- Automation Rules configuradas fora do repositório devem ser verificadas na
  janela;
- não existe cancelamento físico de uma execução n8n em voo; a defesa correta
  é o late guard geracional;
- rollback de migration é destrutivo depois do primeiro uso operacional.
