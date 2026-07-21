# Technical Incidents controlled night window

This runbook is a preparation artifact. It does not authorize deployment,
workflow publication, feature enablement or credential rotation.

## Pinned versions

- repository: `paropeba22/chatwoot`
- branch: `feature/technical-incidents`
- baseline: `fd933c105b22c8fed58fbe10f6cc6d26688ec7a9`
- prepared parent HEAD: `839dea44368cf9e492b804faad8eaec8753c8da9`
- AntiGravity workflow: `8k30Q8FFwvr3lbtu`
- AntiGravity draft: `4b2c8033-1c6f-485f-8770-4ceea73fe0e6`
- AntiGravity published version to preserve:
  `8d433990-e41f-471b-bf32-b8aaed588db7`

Record the final preparation commit and image digest before the window.

## Repository automation and push gate

The versioned GitHub Actions configuration has these triggers:

| Event                     | Branch/filter                     | Effect                                                  |
| ------------------------- | --------------------------------- | ------------------------------------------------------- |
| push                      | `develop`                         | frontend checks, full CE specs, CE/EE image publication |
| push                      | `master`                          | full CE specs and CE/EE image publication               |
| push                      | `v*`                              | CE/EE image publication                                 |
| pull request              | primarily `develop`, some all PRs | lint, tests, size/build checks                          |
| PR touching Central paths | any PR                            | technical-incidents readiness                           |
| workflow dispatch         | manual                            | selected test/image workflows                           |

`technical-incidents-readiness.yml` has no push trigger. A push to
`feature/technical-incidents` does not match a versioned deployment workflow.
`deploy_check.yml` only observes an existing GitHub Deployment/review app; it
does not create a deployment.

This does **not** prove that EasyPanel or another installed GitHub App/webhook
is not configured to deploy every branch. Before any push, inspect:

1. EasyPanel project -> source repository -> tracked branch.
2. EasyPanel project -> auto-deploy/push webhook switch.
3. GitHub repository Settings -> Webhooks: events and branch filtering.
4. GitHub repository Settings -> Installed GitHub Apps.
5. GitHub Environments and deployment branch policies.

Push is forbidden until the external configuration proves that only the
intended production branch/tag can deploy. Capture a screenshot or sanitized
configuration export as window evidence.

## Linux CI review

The readiness workflow uses:

- `pgvector/pgvector:pg16`;
- `redis:7-alpine`;
- Ruby `3.4.4` from `.ruby-version`;
- Node 24 from `.nvmrc` compatibility;
- pnpm `10.2.0` from `package.json`;
- `ruby/setup-ruby` with `bundler-cache: true`, which performs
  `bundle install`;
- `pnpm install --frozen-lockfile`.

This repository's authoritative package manager is pnpm. Running `yarn
install` would use a second lockfile and is intentionally not part of the
readiness workflow.

The workflow performs:

1. full-history checkout for Gitleaks;
2. ESLint and focused Vitest;
3. local AntiGravity extractor tests;
4. PostgreSQL/Redis health checks;
5. RuboCop;
6. empty database create and migration up;
7. exact migration down in reverse order;
8. checks that the table/feature column were removed;
9. exact migration up in forward order;
10. generated schema artifact;
11. Central, contract and affected core RSpec suites;
12. failure if generated `db/schema.rb` differs from Git.

The workflow uses only the built-in `GITHUB_TOKEN`. The repository owner is a
personal account, so the documented Gitleaks Action organization license is
not required. CI is not approved until an actual run is green.

## Migration review and commands

### Static result

- `20260717000001` adds the account feature column and incident table.
- `20260717000002` adds scope, criteria and immutable update tables.
- `20260717000003` adds evaluations, conversation links and deliveries.
- `20260720000001` adds durable outbox dimensions and supporting indexes.
- Foreign keys cover every authoritative association.
- Scope group and criteria deletion cascade only with their parent scope.
- Operational update/delivery associations restrict destructive incident
  deletion.
- Enums and numeric ranges have PostgreSQL check constraints.
- All explicit index/constraint identifiers are below PostgreSQL's 63-byte
  identifier limit.
- Global lifecycle/outbox indexes match global jobs; account-scoped indexes
  match API queries.
- The account boolean default is metadata-only on PostgreSQL 16, but still
  requires a brief `ACCESS EXCLUSIVE` lock.
- Outbox columns are applied to a newly introduced table. With every switch
  off, it should have no operational rows during the first deploy.
- Existing delivery rows, if any, are marked terminal for manual review rather
  than replayed.
- Rolling down `20260720000001` removes the new state dimensions. Rolling down
  `20260717000003`, `20260717000002` and `20260717000001` in that order
  destroys all Central data and is not a production rollback.
- The legacy-state backfill is not data-reversible. Logical rollback must
  preserve the additive schema.

### Linux verification

```sh
export RAILS_ENV=test
export POSTGRES_HOST=127.0.0.1
export POSTGRES_USERNAME=postgres
export POSTGRES_PASSWORD=''

bundle exec rails db:drop db:create db:migrate
bundle exec rails db:migrate:down VERSION=20260720000001
bundle exec rails db:migrate:down VERSION=20260717000003
bundle exec rails db:migrate:down VERSION=20260717000002
bundle exec rails db:migrate:down VERSION=20260717000001
bundle exec rails runner \
  'abort if ActiveRecord::Base.connection.data_source_exists?("technical_incidents")'
bundle exec rails runner \
  'abort if ActiveRecord::Base.connection.column_exists?(:accounts, :technical_incidents_enabled)'
bundle exec rails db:migrate:up VERSION=20260717000001
bundle exec rails db:migrate:up VERSION=20260717000002
bundle exec rails db:migrate:up VERSION=20260717000003
bundle exec rails db:migrate:up VERSION=20260720000001
bundle exec rails db:schema:dump
git diff --check
git diff --exit-code -- db/schema.rb
```

Review `pg_stat_activity`, lock wait time and migration duration before
proceeding in production.

## Server switch proof matrix

| Gate                                                            | Expected result                                             |
| --------------------------------------------------------------- | ----------------------------------------------------------- |
| backend `disabled`                                              | precheck fallback; match fallback; commit blocked           |
| backend `shadow`                                                | precheck/match allowed; commit blocked                      |
| n8n `active`, backend `shadow`                                  | effective mode remains shadow                               |
| account feature off                                             | APIs/jobs cannot act for that account                       |
| outbox off                                                      | commit, dispatcher and worker processing blocked            |
| delivery off                                                    | queued worker releases without message/link/handoff effects |
| API Inbox delivery off                                          | API adapter cannot create/enqueue managed delivery          |
| server changed from active to disabled/shadow after reservation | worker rechecks and releases without effects                |

Dispatcher, processor, status and compatibility retry jobs recheck their
switches. Lifecycle only changes internal incident state and requires the
account feature. Retention only anonymizes/deletes retained data and has no
external effect.

## Chatwoot legacy smoke matrix

Run before publishing any n8n draft:

| Area               | Smoke test                                  | Pass criterion                          |
| ------------------ | ------------------------------------------- | --------------------------------------- |
| conversation       | receive and reply in existing API Inbox     | one incoming and one outgoing event     |
| MessageBuilder     | plain outgoing text and private note        | content/sender/private fields unchanged |
| Message            | normal API outgoing without incident marker | SendReply/webhook behavior unchanged    |
| webhook listener   | ordinary API message                        | exactly one API Inbox webhook           |
| webhook listener   | managed test message with switches off      | no incident webhook                     |
| WebhookJob         | receiver 200, 500 and timeout               | normal error/status behavior            |
| SendReplyJob       | existing API/email continuity case          | existing email behavior unchanged       |
| Channel::Api       | create/update normal conversation message   | API remains compatible                  |
| callback           | PATCH `sent/delivered/read/failed`          | only API Inbox accepts update           |
| labels             | add/remove ordinary label                   | no incident label appears               |
| notes              | create ordinary private note                | private note remains internal           |
| `bot_handoff!`     | existing AgentBot handoff                   | assignment/status/reporting unchanged   |
| AgentBot           | ordinary bot token                          | cannot access Central endpoints         |
| dedicated AgentBot | Central endpoint while disabled             | fallback/blocked, no side effect        |
| Pundit             | agent/admin/custom role                     | 403/allowed matches permissions         |
| feature flag       | disabled account                            | no menu and API unavailable             |
| Custom Roles       | save existing permissions                   | no permission loss                      |
| menu/routes/store  | normal navigation                           | no errors or blank dashboard            |
| Sidekiq            | boot with all switches off                  | schedules load without NameError        |
| cron               | lifecycle/status/dispatcher                 | no external effect while disabled       |

Core files changed relative to `origin/develop` include `Account`,
`Conversation`, `Message`, `Featurable`, `WebhookListener`,
`AccessTokenAuthHelper`, routes, schedule, feature registry, Custom Roles,
sidebar, dashboard routes and store registration. `Messages::MessageBuilder`,
`WebhookJob`, `SendReplyJob` and `Channel::Api` are read-only dependencies and
were not modified.

## AntiGravity regression matrix

Use only internal/fixture conversations while the incidents mode remains off.

| Scenario              | Required check                                         |
| --------------------- | ------------------------------------------------------ |
| first message         | Bia presentation occurs once                           |
| finance               | existing invoice route and state preserved             |
| boleto/Pix/link       | correct invoice, Pix and payment-link outputs          |
| support               | normal diagnostic and Radius route                     |
| registration          | state extraction and continuation                      |
| release               | suspension/release protections and result              |
| scheduling            | normal scheduling route and handoff                    |
| one contract          | automatic selection                                    |
| multiple contracts    | selection is requested only by normal support          |
| index                 | valid index selects correct contract                   |
| street/bairro/cidade  | natural-language selection selects correct contract    |
| invalid answer        | counter advances and existing fallback/handoff occurs  |
| 20-minute expiry      | old selection cleared; new selection required          |
| duplicate webhook     | no duplicate reply/state renewal                       |
| simultaneous messages | aggregator preserves order and one decision            |
| audio                 | transcription enters the normal route                  |
| image                 | image triage route preserved                           |
| sticker               | ignored/fallback without incident execution            |
| handoff               | labels, note and return-human marker preserved         |
| human -> AI           | stale contract selection is not reused                 |
| Radius                | selected support contract is used                      |
| suspension            | no unauthorized release                                |
| incident mode off     | no classifier/precheck/match/commit call               |
| incident shadow       | observation only; no selection question or side effect |

## Evolution/API Inbox static path

```text
Chatwoot outgoing Message
  -> API Inbox message_created webhook
  -> AntiGravity receiver
  -> EvolutionAPI send
  -> provider result/status
  -> PATCH Chatwoot API Inbox message status
  -> delivered/read reconciliation
  -> labels/note/handoff
```

The outgoing webhook contains `message.webhook_data` plus
`event=message_created`. The internal Chatwoot message ID is `id`; conversation
and inbox identifiers are present in the normal webhook payload. Headers are:

- `Content-Type: application/json`;
- `Accept: application/json`;
- deterministic `X-Chatwoot-Delivery`;
- `X-Chatwoot-Timestamp` and `X-Chatwoot-Signature` when the API Inbox has a
  secret.

`WEBHOOK_TIMEOUT` controls the HTTP timeout and defaults to five seconds.
Webhook failure marks the Message `failed`. The outbox later retries with the
same delivery ID. Chatwoot Message statuses are `sent`, `delivered`, `read`
and `failed`.

The expected callback is:

```text
PATCH /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:message_id
api_access_token: <authorized internal token>
{"status":"delivered"}
```

`read`, `failed` and `external_error` follow the same API Inbox-only endpoint.
If delivered/read never arrives, the outbox does not hand off. It retries with
exponential minutes up to eight counted attempts and then becomes
`failed_terminal`.

Delivery is not proven until a non-customer API Inbox and isolated Evolution
receiver demonstrate: exactly one webhook, exactly one provider send, a
provider message ID, delivered/read callback and no duplicate after process
restart. Use an internal test number explicitly allowlisted at both receiver
and Evolution layers.

## Window checklist

### Before the window

1. Confirm external autodeploy configuration and safe branch push.
2. Obtain a green readiness CI run.
3. Commit the generated schema from the actual migration.
4. Obtain and compare the redacted AntiGravity export.
5. Confirm the production image digest and previous rollback image.
6. Take and verify a PostgreSQL backup.
7. Record Redis/Sidekiq queue counts and active jobs.
8. Confirm all account features are off.
9. Confirm server variables:

   ```text
   TECHNICAL_INCIDENTS_AUTOMATION_MODE=disabled
   TECHNICAL_INCIDENTS_OUTBOX_ENABLED=false
   TECHNICAL_INCIDENTS_DELIVERY_ENABLED=false
   TECHNICAL_INCIDENTS_API_INBOX_DELIVERY_ENABLED=false
   ```

10. Confirm AntiGravity is still published at the preserved version.

### Deploy order

1. Pause new deploy activity and quiet only the affected release process.
2. Apply additive migrations with the four server switches off.
3. Verify tables, columns, constraints and indexes.
4. Deploy the pinned web image with automation disabled.
5. Start Sidekiq with outbox/delivery off.
6. Run health, authentication and old Chatwoot smoke matrix.
7. Abort on any old-flow regression.
8. Publish the prepared AntiGravity draft only in `off`, under separate
   authorization.
9. Run the full AntiGravity regression matrix.
10. Enable the account feature only for the internal test account.
11. Set backend to `shadow`; keep outbox and delivery off.
12. Set n8n to shadow and confirm zero deliveries/messages/labels/handoffs.
13. Perform contract checks against the real endpoints.
14. For the isolated internal canary only, enable server active, outbox,
    delivery and API Inbox delivery in that order.
15. Prove Evolution delivery and callback; immediately return switches to off.
16. No wider activation in the same window without a separate go/no-go.

### Proceed criteria

- CI and migrations green;
- schema matches;
- old Chatwoot smoke matrix green;
- AntiGravity regression green in off;
- shadow creates zero external effects;
- queue latency and error rate remain normal;
- no cross-account or unauthorized access;
- no duplicate webhook/message;
- delivered/read callback proved for the internal test.

### Abort criteria

- migration error or lock exceeding the agreed window;
- web/Sidekiq boot error;
- ordinary API Inbox webhook missing or duplicated;
- normal message, financial, support or handoff regression;
- any incident effect while disabled/shadow;
- outbox backlog growing unexpectedly;
- unknown contract response/status;
- callback missing, duplicate Evolution send or customer-number exposure;
- secret found in code, artifact or logs.

### Rollback

1. Set automation disabled and all delivery switches false.
2. Return n8n to off or republish preserved version
   `8d433990-e41f-471b-bf32-b8aaed588db7`.
3. Quiet Sidekiq and inspect pending/processing deliveries.
4. Wait for leases or stop incident queues without deleting evidence.
5. Deploy the previous Chatwoot image.
6. Leave additive tables/columns intact.
7. Restart ordinary queues and repeat the legacy smoke matrix.
8. Use physical migration down only if no incident operation ever occurred
   and a verified backup/export exists.

### Observe

- HTTP status/latency by Central endpoint;
- `technical_incidents.*` events and reason codes;
- outbox counts by state and oldest age;
- webhook status/latency and deterministic delivery ID;
- Message sent/delivered/read/failed transitions;
- Sidekiq retries/dead jobs and Redis errors;
- label/note/handoff completion states;
- duplicate/stale/fallback rates;
- PostgreSQL locks, slow queries and connection pool.
