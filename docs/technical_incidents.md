# Technical Incidents production controls

The form catalog contract, root-cause analysis and UI-only rollout procedure are
documented in `docs/technical_incident_form_catalogs.md`.

This document covers only the hardened V1 implementation. The account feature
and all server-side automation switches are disabled by default.

## Independent safety gates

Set these only through the environment/secret manager:

```text
TECHNICAL_INCIDENTS_AUTOMATION_MODE=disabled|shadow|active
TECHNICAL_INCIDENTS_OUTBOX_ENABLED=false|true
TECHNICAL_INCIDENTS_DELIVERY_ENABLED=false|true
TECHNICAL_INCIDENTS_API_INBOX_DELIVERY_ENABLED=false|true
```

All defaults are `disabled`/`false`. The effective mode is the least
privileged value between the server and the n8n request. `shadow` permits
precheck and match but never commit. A commit requires server `active`, account
feature `technical_incidents`, and the outbox switch. Processing an accepted
commit additionally requires both delivery switches.

Turning any switch off preserves incidents, evaluations, audit and outbox rows.
It cannot recall a message already accepted by an external provider.

## Authoritative flow

```text
AntiGravity classification
  -> HTTPS + dedicated account AgentBot + throttling
  -> semantic gate (server thresholds)
  -> SQL candidate prefilter and deterministic rank/match
  -> opaque evaluation
  -> commit revalidation under row locks
  -> transaction reserves one delivery/outbox row and accepts evaluation
  -> commit
  -> periodic PostgreSQL dispatcher
  -> one isolated delivery worker
  -> link
  -> literal message
  -> API Inbox webhook enqueue with deterministic X-Chatwoot-Delivery
  -> external delivered/read status
  -> labels
  -> private note
  -> bot handoff
  -> audit
```

No message, webhook, label, note or handoff is executed inside the commit
transaction. Redis failure cannot discard the operation because the periodic
dispatcher scans PostgreSQL. Processing uses a lease, watchdog and independent
states for outbox, message, transport, link, labels, note, handoff and audit.

The only enabled adapter is `Channel::Api`. Managed incident messages bypass
the generic API Inbox webhook callback and are enqueued once by the durable
adapter with a deterministic delivery header. Other inboxes fail closed. Email
and native channel support require a separate, explicitly tested adapter.

The Grupo Telecom delivery path found in this repository is:

```text
outgoing Message
  -> API Inbox message_created webhook
  -> external AntiGravity/Evolution integration
  -> external message status callback
  -> Message delivered/read
```

`SendReplyJob` maps `Channel::Api` to email continuity, not to EvolutionAPI.
Therefore a database Message and a successful Sidekiq enqueue are not proof of
WhatsApp delivery. `TECHNICAL_INCIDENTS_API_INBOX_DELIVERY_ENABLED` must remain
false until the real-environment procedure below passes.

## Semantic policy

Server thresholds default to medium `0.70` and high `0.85`; n8n cannot override
them. Invalid/low confidence, `topic_change=true`, `needs_clarification=true`,
unknown problem types and unknown service keys are non-executable. Medium
confidence permits only exact `contract_id` or `pop_id`. Postal code,
city/neighborhood, city/street, service-specific and general matches require
high confidence. Commit and outbox processing revalidate the same policy.

## V1 API contract

All four endpoints require HTTPS in production and the same dedicated,
account-owned AgentBot marker (`bot_config.technical_incidents_api=true`).
Account identity comes from the token. Rack throttles IP+endpoint and
token-digest+endpoint; the controller adds account+endpoint throttling.

```text
POST /api/v1/technical_incident_checks/precheck
POST /api/v1/technical_incident_checks/:opaque_id/match
POST /api/v1/technical_incident_checks/:opaque_id/commit
POST /api/v1/technical_incident_evaluations/:opaque_id/feedback
```

Contract version is `1.0`. Commit body is empty. Canonical no-match status is
`no_candidate`; `no_match` is not emitted by Chatwoot. The opaque identifier is
returned as `id`, `check_id`, `evaluation_id` and `commit_token` for V1 adapter
compatibility. Match accepts at most 20 sanitized contracts.

The live MCP confirms workflow `8k30Q8FFwvr3lbtu`, draft
`4b2c8033-1c6f-485f-8770-4ceea73fe0e6`, published version
`8d433990-e41f-471b-bf32-b8aaed588db7`, and the five required contract node
names. The MCP read API did not expose Code node source. The field-level
comparison is recorded in `docs/technical_incidents_contract_diff.md`; manual
Code export/hash confirmation remains a production gate.

## Template safety

Customer content is plain text. Only these exact outputs are allowed:

```text
{{estimated_resolution_at}}
{{affected_service}}
{{incident_title}}
```

Unknown outputs, Liquid tags, filters, loops, includes and nested expressions
block activation/update. API Inbox is the only delivery adapter; Email and
other channels fail closed rather than passing content through a Liquid-aware
builder.

## Expand/contract deployment

Do not deploy until the dedicated readiness workflow is green and the
generated `db/schema.rb` from a real Rails migration run has been reviewed and
committed.

1. Record the application SHA and take a PostgreSQL backup.
2. Keep AntiGravity `off`, account feature disabled, and all four backend
   switches disabled/false.
3. Build an image containing code that tolerates absent outbox columns; deploy
   migrations before starting this revision's web/Sidekiq processes.
4. Run in Linux/CI:

   ```sh
   bundle exec rails db:migrate
   bundle exec rails runner 'abort unless ActiveRecord::Base.connection.data_source_exists?("technical_incident_deliveries")'
   bundle exec rails runner 'abort unless TechnicalIncidentDelivery.column_names.include?("outbox_state")'
   ```

5. Start web with automation disabled. Run health, UI-hidden, HTTPS,
   unauthorized-token and disabled-mode smoke tests.
6. Start Sidekiq with outbox disabled and confirm cron loads without NameError.
7. Enable only the account feature for an internal account; keep server
   automation disabled.
8. Enable server `shadow`; verify no deliveries are reserved.
9. After real contract and Evolution tests, enable outbox/delivery only for the
   controlled canary window. Server `active` is the final independent switch.

PostgreSQL queries requiring real `EXPLAIN (ANALYZE, BUFFERS)` before canary:

```sql
SELECT id FROM technical_incidents
 WHERE status = 'active' AND archived_at IS NULL AND expires_at <= now();
SELECT id FROM technical_incident_deliveries
 WHERE outbox_state IN ('pending','retry')
   AND (next_retry_at IS NULL OR next_retry_at <= now())
 ORDER BY next_retry_at, id LIMIT 200;
SELECT id FROM technical_incident_deliveries
 WHERE outbox_state = 'processing' AND locked_at < now() - interval '5 minutes';
```

## Queue-safe rollback

Logical rollback is preferred because delivered messages and immutable audit
cannot be undone.

1. Set server automation to `disabled`; set outbox and both delivery switches
   false; keep AntiGravity `off`.
2. Stop cron scheduling and quiet workers:

   ```sh
   bundle exec sidekiqctl quiet tmp/pids/sidekiq.pid
   ```

   For containers, scale Sidekiq to zero after it becomes quiet.

3. Inspect and export:

   ```sh
   bundle exec rails runner 'puts TechnicalIncidentDelivery.group(:outbox_state).count.to_json'
   bundle exec rails runner 'puts TechnicalIncidentDelivery.where(outbox_state: "processing").count'
   ```

4. Wait for active jobs to finish or terminate only after their leases expire.
   Do not drain pending incident jobs into a revision whose classes are absent.
5. Deploy the previous application revision. Leave additive tables/columns in
   place. Restart web and non-incident Sidekiq queues.
6. Verify inbox delivery, Evolution, labels, assignment and normal routes.

Physical rollback is destructive and only allowed when no incident was ever
enabled or after a verified export. Address the migrations by exact version so
an unrelated migration can never be rolled back:

```sh
bundle exec rails db:migrate:down VERSION=20260720000001
bundle exec rails db:migrate:down VERSION=20260717000003
bundle exec rails db:migrate:down VERSION=20260717000002
bundle exec rails db:migrate:down VERSION=20260717000001
```

This removes the outbox hardening and then all incident data. It cannot retract
external webhooks/messages, notifications or handoffs already completed.
Audit evidence exported before rollback must be retained. Jobs referring to
removed classes must be deleted from Redis or drained before code downgrade.

## Required real-environment Evolution test

Use a non-customer API Inbox wired to the same type of Evolution listener:

1. Keep AntiGravity production workflow unchanged; use an isolated receiver.
2. Enable all backend switches only for the test process/account.
3. Commit one fixture incident and record delivery ID, message ID and
   `X-Chatwoot-Delivery`.
4. Verify exactly one API Inbox webhook, exactly one Evolution send, provider
   message ID, and Chatwoot delivered/read callback.
5. Kill Sidekiq after reservation, after enqueue and after provider acceptance;
   restart and verify no duplicate customer message.
6. Verify labels, note and handoff occur only after delivered/read.
7. Repeat with provider timeout, HTTP 500, Redis outage and unsupported inbox.
8. Disable all switches and retain sanitized evidence.

## Secret mitigation and rotation

No tracked Chatwoot file or tracked workflow export contains a detected
credential after the local scan. Historical local n8n exports outside this
repository contain API-key-shaped values and must be moved to encrypted
storage or securely deleted by the operator.

Manual production rotation remains mandatory:

1. Inventory each affected n8n node by credential type without copying values.
2. Create replacement credentials in the n8n credential store/secret manager.
3. Update nodes in a new draft and test each integration.
4. Publish only with separate authorization and a rollback credential.
5. Revoke old provider keys after successful verification.
6. Re-run the secret scanner over Git history, artifacts and backups.

Code mitigation is complete; production rotation is not.
