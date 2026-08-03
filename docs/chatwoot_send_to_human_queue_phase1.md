# Chatwoot: Fase 1 — Enviar para fila

## Escopo e estado de segurança

Esta fase implementa apenas a transição manual `send_to_human_queue`. Ela não implementa retorno para a Bia, ações em lote, revisão global das abas/contadores ou automação de inatividade. O AntiGravity não é alterado.

A funcionalidade é protegida pela feature flag de conta `conversation_send_to_human_queue`, criada desativada por padrão. Como o bitmap legado já ocupa todos os bits seguros do `bigint`, a flag usa a coluna booleana dedicada `accounts.conversation_send_to_human_queue_enabled`, integrada ao `Featurable` pelo mesmo padrão de `technical_incidents`. Com a flag desativada, o item não aparece no frontend e o endpoint responde `404 feature_disabled` sem alterar a conversa.

## Contrato HTTP

```http
POST /api/v1/accounts/:account_id/conversations/:conversation_id/automation_transitions
Content-Type: application/json
```

`conversation_id` é o `display_id` da conversa na conta autenticada.

```json
{
  "action": "send_to_human_queue",
  "idempotency_key": "queue-<uuid>",
  "expected_last_message_id": 123
}
```

- `action`: obrigatório e, nesta fase, aceita somente `send_to_human_queue`.
- `idempotency_key`: obrigatório, entre 8 e 128 caracteres, restrito a letras, números, ponto, sublinhado, dois-pontos e hífen.
- `expected_last_message_id`: opcional. Quando informado, deve ser o ID da mensagem não-atividade mais recente.

Resposta aceita ou idempotente:

```json
{
  "status": "accepted",
  "reason_code": "sent_to_human_queue",
  "transition_id": 42,
  "conversation": {}
}
```

Retries da mesma chave retornam `status=duplicate` e `reason_code=idempotency_replay`. Uma conversa já integralmente projetada na fila retorna `duplicate/already_in_human_queue`, sem nova nota ou novo registro funcional.

| HTTP | Condição | Comportamento |
| --- | --- | --- |
| 401 | usuário autenticado sem acesso/permissão, conforme o handler Pundit existente | nenhuma alteração |
| 404 | conta/conversa inexistente ou feature desligada | nenhuma exposição entre contas |
| 409 | `expected_last_message_id` desatualizado | devolve a conversa autoritativa atual |
| 422 | action, chave ou ID inválido; falha de persistência | transação revertida |

## Transação, lock e estado final

O serviço `Conversations::AutomationTransitionService` carrega a conversa exclusivamente pela conta atual e usa `Conversation#with_lock`. Autorização, feature flag, idempotência, última mensagem e estado são revalidados dentro do lock.

Na mesma transação são persistidos a projeção da conversa, uma nota privada e o registro estruturado de auditoria/idempotência.

| Campo | Valor final |
| --- | --- |
| status | `open` |
| assignee humano | `nil` |
| assignee AgentBot | `nil` |
| `bot-bia` | removida |
| `aguardando-humano` | adicionada |
| outras labels | preservadas |
| `bia_retorno_humano_pendente` | `true` |
| `waiting_since` | preservado ou preenchido quando ausente |

O serviço usa o callback normal de `Conversation`, inclusive eventos de status, atribuição, labels e `conversation.updated`. Um marcador transitório no model apenas impede autoassignment ao reabrir a conversa durante esta operação; ele não usa `update_columns` nem suprime os eventos normais.

Com os filtros atuais, essa projeção pertence a “Em fila”, não pertence a “Com IA” (sem `bot-bia`) e não pertence a “Meus Atendimentos” (sem assignee).

## Estados da Bia

Os hashes `financeiro_state`, `cadastro_state`, `suporte_state` e `transferencia_state`, além de seleções de contrato/fatura, contexto de mídia, tentativas e `liberacao_ativa`, são preservados para consulta pelo humano. Eles não são reinterpretados nem parcialmente apagados pelo Chatwoot.

A pausa autoritativa nesta fase é composta por `aguardando-humano`, ausência de `bot-bia` e `bia_retorno_humano_pendente=true`. O Guard atual do AntiGravity encerra o fluxo antes de consumir os estados quando `aguardando-humano` está presente. Uma futura ação de retorno para a Bia deverá decidir explicitamente quais estados podem ser retomados; isso pertence à Fase 2.

## Idempotência, concorrência e auditoria

A tabela aditiva `conversation_automation_transitions` possui unicidade em `account_id + conversation_id + action + idempotency_key`.

O lock pessimista serializa dois agentes ou dois retries concorrentes. O primeiro aplica a projeção; o segundo recebe replay da mesma chave ou `already_in_human_queue` para uma chave diferente. Nenhuma nota é duplicada.

O registro estruturado guarda conta, conversa, ator, ação, chave, estado anterior/final sanitizado, motivo, nota associada e timestamps. Os snapshots contêm somente status e indicadores booleanos; não armazenam conteúdo, telefone, CPF ou credenciais. A nota privada informa quem enviou a conversa à fila.

Falhas antes do commit revertem conversa, nota e auditoria. Falhas de validação/persistência produzem log estruturado com IDs internos e `reason_code`, sem payload do cliente.

## Autorização

O backend usa `ConversationPolicy#send_to_human_queue?`:

- administrador: permitido segundo a política normal da conta;
- agente comum: permitido somente com acesso ao inbox ou equipe da conversa;
- Custom Role: exige acesso à conversa e a permissão `conversation_send_to_queue`.

Conta e conversa são sempre derivadas da URL autenticada e consultadas com escopo de conta. A UI não é a barreira autoritativa.

## Frontend e realtime

`MoreActions.vue` mostra “Enviar para fila” quando flag, permissão e estado permitem. A ação abre confirmação, bloqueia nova interação durante confirmação/request, envia uma única chamada, não aplica sucesso otimista e atualiza a store pela conversa devolvida pelo backend. Em `409`, aplica a conversa autoritativa e mostra conflito. Metacontadores são reconsultados após accepted, duplicate ou conflict.

A mutation existente `UPDATE_CONVERSATION` rejeita payload com `updated_at` inferior ao estado local. Assim, uma resposta HTTP antiga não sobrescreve um evento ActionCable mais novo. Os problemas globais de corrida entre requests de contadores permanecem reservados para a Fase 3.

## Eventos e contrato com o AntiGravity

As alterações geram eventos Chatwoot normais depois do commit. A nota é privada; não é uma mensagem pública ao cliente. O webhook da transição não tem `message_type=incoming`, portanto não inicia rota financeira/suporte. Para uma mensagem futura do cliente, o Guard do AntiGravity encontra `aguardando-humano` e encerra sem resposta automática.

Risco residual: uma execução do AntiGravity que já tenha ultrapassado o Guard antes do clique não pode ser cancelada pelo Chatwoot nesta fase. O teste conjunto dessa janela estreita e uma futura sessão/epoch versionada pertencem à Fase 5/Fase 2, respectivamente.

## Feature flag

Ativação gradual, somente após deploy e smoke tests com a flag desligada:

```ruby
account.enable_features!('conversation_send_to_human_queue')
```

Kill switch:

```ruby
account.disable_features!('conversation_send_to_human_queue')
```

Desligar a flag oculta a ação e bloqueia novas transições. Dados e auditoria já gravados são preservados.

## Testes focais

```bash
bundle exec rails db:migrate RAILS_ENV=test
bundle exec rspec \
  spec/models/conversation_automation_transition_spec.rb \
  spec/policies/conversation_policy_spec.rb \
  spec/enterprise/policies/enterprise/conversation_policy_spec.rb \
  spec/services/conversations/automation_transition_service_spec.rb \
  spec/services/conversations/automation_transition_service_concurrency_spec.rb \
  spec/requests/api/v1/accounts/conversation_automation_transitions_spec.rb

pnpm vitest run \
  app/javascript/dashboard/api/specs/inbox/conversation.spec.js \
  app/javascript/dashboard/store/modules/specs/conversations/actions.spec.js \
  app/javascript/dashboard/store/modules/specs/conversations/getters.spec.js \
  app/javascript/dashboard/store/modules/specs/conversations/mutations.spec.js \
  app/javascript/dashboard/components/widgets/conversation/specs/MoreActions.spec.js
```

## Deploy manual de madrugada

1. Confirmar backup de PostgreSQL, SHA aprovado e filas saudáveis.
2. Confirmar a flag desligada em todas as contas.
3. Executar a migration aditiva pelo release command da imagem aprovada.
4. Verificar tabela, constraints, FKs e índice único.
5. Subir web e workers compatíveis, ainda com a flag desligada.
6. Executar smoke tests do Chatwoot antigo: receber/responder internamente, atribuir, desatribuir, label, nota privada, resolver/reabrir e realtime.
7. Observar erros Rails/Sidekiq/ActionCable e latência.
8. Ativar somente na conta interna/autorizada.
9. Validar uma conversa interna em cada estado `open`, `pending`, `snoozed` e `resolved`; validar duplo clique e conflito 409.
10. Confirmar projeção nas abas, contadores e bloqueio da Bia.
11. Expandir somente após a janela de observação aprovada.

## Rollback

O primeiro rollback é desligar a feature flag. Isso interrompe novas transições sem remover auditoria nem exigir downgrade.

Se houver regressão de código, manter a flag desligada, reverter a imagem para o SHA anterior e manter a tabela aditiva. Código anterior ignora a tabela.

Não executar `db:rollback` depois de uso operacional sem exportar e aprovar a perda dos registros de auditoria. A migration é tecnicamente reversível, mas a remoção da tabela é destrutiva para dados já produzidos.

## Limitações e fases seguintes

- Fase 2: “Devolver para a Bia”, invalidação/retomada de estados e eventual session epoch.
- Fase 3: tornar tabs e contadores projeções exclusivas e eliminar races globais.
- Fase 5: teste conjunto Chatwoot + AntiGravity, incluindo execução já em voo.
- Automation Rules configuradas em runtime devem ser inventariadas na janela, pois não estão no repositório.
