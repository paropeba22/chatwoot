# Technical Incidents Center

This document describes the V1 implementation for the customized Chatwoot and
the read-only integration contract prepared for the AntiGravity workflow.

## Safety defaults

- The account feature `technical_incidents` is disabled by default.
- The AntiGravity draft remains unchanged with
  `technical_incidents_mode=off`.
- Disabling the Chatwoot feature hides the menu, denies UI APIs, rejects new
  automation evaluations and commits, and prevents delivery retries.
- Existing records, audit updates, links and delivery state remain preserved.
- A `shadow` evaluation can precheck and match, but the commit service rejects
  it with `evaluation_not_active_mode`.

The existing `feature_flags` bigint already consumes all 63 safe positive
bits. To avoid shifting or corrupting any existing flag, this feature is the
only entry stored in the dedicated `accounts.technical_incidents_enabled`
boolean. It still uses the standard `feature_enabled?`, `enable_features!`,
`disable_features!`, `all_features` and frontend feature list APIs.

## Architecture

The UI is account scoped and uses the existing Vue 3 dashboard, Vuex API
client, route permissions, design tokens and Pundit context. The backend owns
incident lifecycle, scope validation, ranking, template rendering, audit and
all side effects.

The normalized V1 flow is:

```text
AntiGravity semantic classification
  -> POST /api/v1/technical_incident_checks/precheck
  -> optional POST /api/v1/technical_incident_checks/:opaque_id/match
  -> active mode only: POST /api/v1/technical_incident_checks/:opaque_id/commit
  -> Message after_commit -> SendReplyJob -> configured inbox channel
  -> delivery status reconciliation / retry
  -> optional POST /api/v1/technical_incident_evaluations/:opaque_id/feedback
```

The commit endpoint accepts no incident, message, scope or status in its body.
It resolves the opaque evaluation, locks the account, evaluation and incident,
revalidates the feature, active mode, semantic compatibility, deterministic
scope, incident window and notification version, then reserves the unique
delivery.

The message is created through `Messages::MessageBuilder`. Chatwoot's existing
`Message` callback queues `SendReplyJob`, so WhatsApp/EvolutionAPI and every
other configured inbox continue through their existing provider path. Delivery
is only marked `delivered` after a channel status updates the Message to
delivered/read. A database insert alone is not delivery confirmation.

## V1 automation contract

Authentication uses a dedicated, account-owned AgentBot with
`bot_config.technical_incidents_api=true` and its access token in the
`api_access_token` header. That marker restricts this AgentBot token to the four
incident automation actions; regular AgentBot tokens cannot call them. The
account is derived from the token and is never accepted from the request.
Production requests require HTTPS. The token is rate limited by a SHA-256
digest and is never written to logs or exposed to the frontend.

### Precheck

`POST /api/v1/technical_incident_checks/precheck`

Required V1 fields are represented by
`spec/fixtures/technical_incidents/v1/precheck_request.json`. The response
contains `contract_version`, `status`, `reason_code` and an opaque identifier
under the compatible aliases `id`, `check_id`, `evaluation_id` and
`commit_token`. The identifier expires after 20 minutes.

Precheck never trusts an incident identifier from automation and never sends a
message, changes labels or performs handoff.

### Match

`POST /api/v1/technical_incident_checks/:opaque_id/match`

Only the sanitized fields in the V1 fixture are accepted. CPF/CNPJ, names,
phones, credentials, PPPoE data, MAC, financial links, reference points and
notes are rejected. `pop_name` is display-only. City, neighborhood and street
come only from postal location fields.

The deterministic order is contract ID, POP ID, postal code, city plus
neighborhood, city plus street, service-specific, then general. OR applies
between groups, AND between different criteria in a group, and OR between
values of the same criterion. Exact ranking ties return `ambiguous`.

### Commit

`POST /api/v1/technical_incident_checks/:opaque_id/commit`

The body is empty. The unique delivery key is equivalent to:

```text
conversation_id:incident_id:notification_version:delivery_kind
```

The database also uniquely protects request IDs and non-null source message
IDs. A concurrent or repeated commit returns `duplicate`. A new conversation
or notification version produces a different key.

Within one database transaction the service creates the conversation link,
literal backend-rendered message, labels, private note, bot handoff state and
audit update. The outbox delivery state progresses through `reserved`,
`message_created`, `delivery_queued`, `handoff_completed`, `delivered`,
`failed_retryable` or `failed_terminal`.

### Feedback

`POST /api/v1/technical_incident_evaluations/:opaque_id/feedback`

Controlled values are `correct_match`, `false_positive`, `false_negative`,
`wrong_contract`, `wrong_category`, `duplicate_message` and `other`.

## Data and retention

All seven tables carry `account_id`, foreign keys and account consistency
validations. Incident edits use optimistic locking. Operational commits use
row locks and unique indexes. Audit updates are immutable in the application.

Evaluation payloads are anonymized after 180 days while retaining their
referential record. Audit updates remain for five years, then are purged by a
bulk retention job. Full CPF, telephone, credentials and full addresses are
not accepted into automation audit payloads.

## Lifecycle

Only `active` incidents intercept. `monitoring` never intercepts. Initial
activation defaults to six hours and cannot exceed seven days. Scheduled
incidents need a future start and activate only when due. Reopening requires a
new future expiration and increments `notification_version`.

Message, ETA, affected service, problem taxonomy, action, active window or
scope decision changes invalidate old evaluations by incrementing
`notification_version`. Internal-note-only changes do not.

The lifecycle job activates scheduled records, expires active records, records
review alerts and records a forgotten-incident alert after two hours without
an update. Delivery reconciliation and retry jobs are idempotent.

## One controlled deployment

1. Keep AntiGravity `technical_incidents_mode=off`.
2. Back up PostgreSQL and record the deployed Chatwoot commit.
3. Deploy this application revision once with `technical_incidents` still
   disabled for every account.
4. Run `bundle exec rails db:migrate`.
5. Restart web and Sidekiq processes so routes, models and cron entries load.
6. Verify health, Sidekiq queues, migration version and that the incident menu
   and APIs remain unavailable while the flag is off.
7. Create a dedicated account-owned AgentBot for AntiGravity in the target
   environment, set `bot_config.technical_incidents_api=true`, and store its
   token in the environment secret manager. Do not reuse the Bia AgentBot.
8. Enable `technical_incidents` only for an internal test account.
9. Run UI, permission and V1 contract smoke tests without changing
   AntiGravity.
10. In a separately authorized change, configure the Chatwoot base URL, V1
    path, timeout and dedicated token in AntiGravity; switch to `shadow` only
    after smoke tests. `active` requires another explicit authorization.

## Rollback

The immediate safe rollback is to keep AntiGravity `off` and disable
`technical_incidents` for all accounts. This stops new evaluations, commits,
messages, handoffs and retries while preserving evidence.

Roll back the application revision and restart web/Sidekiq. Leave the new
tables in place during an operational rollback; they are additive and inert
without the code. Only run `bundle exec rails db:rollback STEP=1` in an
isolated maintenance window when the feature was never enabled or after a
verified export, because that rollback intentionally removes incident data.

After rollback, verify that the main Chatwoot inbox, EvolutionAPI delivery,
labels, assignment, scheduled jobs and existing routes operate normally.
