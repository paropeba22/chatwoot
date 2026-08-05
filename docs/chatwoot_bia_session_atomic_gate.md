# Bia session atomic gate

## Scope and safety state

This stacked change extends the Phase 2 branch and does not include the
technical-incident form branch. It adds account-scoped compare-and-set (CAS)
operations for the Bia session. Both conversation automation feature flags
remain disabled by default. No production migration, workflow publication, or
external message is part of this change.

## Root cause

The generic conversation custom-attributes endpoint assigns the submitted
object to `conversation.custom_attributes` and saves it. It does not merge
under a conversation lock, compare a session generation, or provide durable
idempotency. A workflow that read generation N could therefore submit a stale
object after a manual transition incremented the session to N+1, restoring N
and discarding unrelated concurrent attributes.

The generic endpoint remains available for legacy callers. Strict Bia-session
operations must not use it.

## Endpoints

### Reset context

`POST /api/v1/accounts/:account_id/conversations/:conversation_id/bia_session/reset_context`

```json
{
  "expected_generation": 5,
  "source_message_id": 1234,
  "idempotency_key": "bia-reset-opaque-key",
  "reset_profile": "bia_session_v1"
}
```

The backend locks the conversation, reloads authoritative state, validates the
generation and source message, and applies a server-owned reset profile. The
request cannot write custom attributes, labels, assignments, state, or the
generation. Unknown attributes are preserved.

### Guarded public message

`POST /api/v1/accounts/:account_id/conversations/:conversation_id/bia_session/messages`

```json
{
  "expected_generation": 5,
  "source_message_id": 1234,
  "idempotency_key": "bia-send-opaque-key",
  "content": "response",
  "content_type": "text",
  "private": false
}
```

Version 1 accepts text-only public messages. The conversation lock covers the
final session validation, canonical message creation, and operation ledger.
Attachments and templates are deliberately not accepted until their canonical
delivery contracts can be guarded without changing behavior.

### Automation transitions

The existing automation-transition endpoint accepts
`expected_session_generation`. It is mandatory for `return_to_bia` and
optional for legacy/manual queue calls. Strict workflow handoffs must supply
it. Generation is checked inside the same pessimistic lock as the projection.

## Canonical reset profile

`bia_session_v1` preserves unknown keys, history references, presentation
state, stable contract or invoice references, and audit/configuration data. It
removes a small explicit allowlist of top-level transient controls and transient
state-machine keys inside `financeiro_state`, `suporte_state`,
`cadastro_state`, and `transferencia_state`. It never replaces the entire
custom-attributes object and never changes generation, state, or resume
boundary.

The operation records JSON byte size before and after without storing the full
attributes or message content.

## Idempotency and audit

`conversation_bia_session_operations` stores only identifiers, operation,
generation, source/result message references, reason codes, restricted session
snapshots, byte counts, and timestamps. A unique index on account,
conversation, operation, and idempotency key provides durable replay
protection. Reusing a key for another generation or source is a conflict.

## Result contract

- `200 accepted/context_reset_applied` or `accepted/message_created`;
- `200 duplicate/idempotency_replay`;
- `409` with an authoritative minimal session snapshot for stale generation,
  stale source, invalid state, human ownership, queue labels, missing Bia
  label, reset state, or closed conversation;
- `404 feature_disabled`;
- `401/403` according to existing account/token policy;
- `422` for invalid generation, source, key, reset profile, content type, or
  payload.

## TOCTOU matrix

| Effect | Previous window | Mitigation in strict mode | Residual state |
| --- | --- | --- | --- |
| Reset custom attributes | GET then whole-object update | CAS reset under conversation lock and restricted merge | Closed |
| Manual/automatic handoff | Guard then independent labels/state/note/assignment calls | Transactional `send_to_human_queue` with expected generation | Closed when strict caller uses endpoint |
| Return to Bia | UI read then projection | Transactional transition with expected generation | Closed |
| Public text message | Late guard then generic message request | Guarded message creation and ledger under conversation lock | Closed for text V1 |
| Attachment/template send | Late guard then channel-specific send | Not accepted by guarded V1 | **Activation blocker for strict paths that need it** |
| Generic custom-attribute write | Guard then stale full-object update | Strict workflow must use CAS/transition operations | Legacy endpoint remains unsafe for strict session writes |
| Labels/assignee/status | Guard then multiple requests | Strict workflow must use an automation transition | Direct strict writes remain blocked |
| SGP/Radius/liberation/registration | Guard then external request | Immediate guard, deterministic idempotency key, operation ledger/claim required | No distributed atomicity; irreversible strict paths stay blocked pending adapter proof |
| Private note | Guard then note creation | Transition audit note is in the same database transaction | Closed for transitions |

There is no claim of atomicity across Chatwoot and external systems. A database
lock cannot span EvolutionAPI, SGP, Radius, or another provider. Any strict
irreversible path without a provider idempotency contract remains blocked for
activation and must fail safely to human handoff.

## Migration and rollback

The migration is additive: one nullable integer on the existing transition
table and one operation ledger with foreign keys, checks, and indexes. Before
release it must pass PostgreSQL 16 up/down/up. In production rollback, disable
the two account feature flags first. Keep the additive schema and audit rows;
do not run `down` after live use without reconciliation.

## Required release checks

- focused service/request/policy/model specs;
- real PostgreSQL two-thread replay and stale-generation races;
- Phase 1 and Phase 2 regression specs;
- frontend API/store/MoreActions specs;
- migration up/down/up on PostgreSQL 16;
- changed-file RuboCop, ESLint, Prettier, Vitest, `git diff --check`, and secret
  scan;
- AntiGravity V2 contract tests before any publication.
