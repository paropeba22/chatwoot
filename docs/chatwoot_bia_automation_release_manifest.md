# Chatwoot + Bia automation controlled-release manifest

## Release status

This manifest prepares a manual overnight window. It does not authorize a
merge, deploy, migration in production, AntiGravity publication, feature
activation, or customer test. The current release status is **blocked for
activation** until the strict AntiGravity paths with heterogeneous public
senders and irreversible external SGP/Radius effects have an approved atomic
or provider-idempotent contract.

## Source stack

| Layer | Branch / PR | Dependency | Default state |
| --- | --- | --- | --- |
| Phase 1 — human queue | `agent/chatwoot-send-to-human-queue`, PR #3 | `develop` | flag off |
| Phase 2 — return to Bia | `agent/chatwoot-return-to-bia`, PR #5 | Phase 1 | flag off |
| Atomic session gate | `agent/chatwoot-bia-session-atomic-gate`, PR #6 | Phase 2 | flags off |
| Incident form | `agent/chatwoot-incident-form-catalog-fix`, PR #4 | independent `develop` | Central off |
| Phase 3 — canonical tabs | `agent/chatwoot-realtime-tabs-counters`, PR #7 | atomic gate | flag off |
| Phase 4 — inactivity shadow | `agent/chatwoot-inactivity-shadow`, PR #8 | Phase 3 | flag off; no schedule |

The incident-form branch is not included in the stacked transition branches.
Before integration, record the reviewed head SHA of every PR and retarget each
stacked PR only after its parent is merged.

## Reviewed heads and readiness evidence (2026-08-11)

| Layer | Reviewed head | Readiness evidence |
| --- | --- | --- |
| Phase 1 / PR #3 | `48b13a790c9fed2bc4c5d9cd04a65c2d94ae51a1` | parent of Phase 2; flag off |
| Incident form / PR #4 | `4a61f4b8f37adb3e2ff2d30f509d0a4b936c1123` | independent; Central off |
| Phase 2 / PR #5 | `ec3b65577e368cfb725cdd5eae339b983cf99034` | parent of atomic gate; flag off |
| Atomic session gate / PR #6 | `c22eff7019f0e418093be79685d278d3afdaaa05` | run `31516880952` green |
| Phase 3 / PR #7 | `3f3cc2f21e87ebce8a4220101f342233d6191a8c` | run `31516948605` green |
| Phase 4 implementation and generated schema / PR #8 | `bf6d64a7da1195052cf70c84baf0a9ef6404aa51` | code run `31517715687` green; flag off; no schedule |

Rails generated and uploaded each schema; no schema was edited manually:

- CAS artifact `9111483154`, digest
  `sha256:ba97dda52b17ca88d76c7980ee86e7fb460dd935ce195091f2f125e6c688e3fe`;
- Phase 3 artifact `9111703031`, digest
  `sha256:74ddc14ffb7635c40c5b8c1c0a98d3d1c1d8e3091efc0ed0b23116cb696e660f`;
- Phase 4 artifact `9111811000`, digest
  `sha256:210a00a6cdb759ad897e0b7dfc4e4b487c7b816dd8004a7b56c778e696445d4d`.

The deterministic AntiGravity session/CAS harness passed 49 of 49 scenarios.
This evidence does not remove the activation blockers documented below.

## AntiGravity inventory

- workflow: `8k30Q8FFwvr3lbtu`;
- active stable version: `4ec83b46-b85c-4413-85cd-c33e7588f9f3`;
- Session Gate V1 draft preserved: `2eb0e314-0311-450b-b0b1-87c14bce7682`;
- Atomic Session Gate V2 draft: `669bfd54-0793-4e59-bd23-d705515157bb`;
- V2 topology: 677 nodes and 843 connections;
- V2 serialized SHA-256: `B10C573FB5B561195C38C4D10B2BC5A1CAF0A2AFD84E06BCAA01343BE8004F02`;
- active backup: `artifacts/antigravity/backups/AntiGravity_8k30Q8FFwvr3lbtu_active_4ec83b46_2026-08-05.json` (local only, never commit);
- active backup SHA-256: `EF72BE325B68E0109E55461AF220B7A8B58342FDAB0A56F12CC7E028E9C90EB0`.

At closeout on 2026-08-11, a fresh read-only MCP query no longer reported the
original baseline as active. It reported workflow version
`e75638c3-5f04-4e03-9bdc-96754f379a3e` as both the current and active version,
with 686 nodes and 659 connection sources, updated at
`2026-08-11T17:09:28.208Z`. Its saved-version metadata says it was authored
via MCP as `Preflight legacy/strict backward-compatible` and describes itself
as unpublished. This inconsistency must be reconciled in the n8n UI/API before
the overnight window; this work did not publish, restore, or otherwise mutate
the workflow during the revalidation.

V2 uses the Chatwoot CAS reset and preserves Entry, Pre-Write, Pre-Send, Late
Guard, legacy/strict mode, fail-closed routing, and Central-off gates. It is not
approved for publication while the active-version discrepancy, direct
heterogeneous EvolutionAPI senders, and irreversible external operations
retain unresolved risk.

## Migrations

Apply only after database backup and only with web/workers built from the same
reviewed image:

1. `20260803000001_create_conversation_automation_transitions`;
2. `20260804000001_add_return_to_bia_automation_transition`;
3. `20260805000001_create_conversation_bia_session_operations`;
4. `20260806000001_add_operational_buckets_to_accounts`;
5. `20260807000001_create_conversation_inactivity_shadow_assessments`.

All are additive. CI must prove PostgreSQL 16 up/down/up and upload the Rails
generated schema. Assess lock duration on a production-sized clone. Do not run
`down` after live feature use without reconciling audit/operation rows.

## Feature flags and activation order

All flags start `false`:

1. `conversation_send_to_human_queue`;
2. `conversation_return_to_bia`;
3. `conversation_operational_buckets`;
4. `conversation_inactivity_shadow`.

Technical Incidents must remain off end to end:
`technical_incidents_mode=off`, `active_commit_enabled=false`, and
`backend_active_authorized=false`.

## Future integration order (do not execute now)

1. merge PR #3;
2. retarget and merge PR #5 to `develop`;
3. retarget and merge PR #6;
4. merge independent PR #4 at a reviewed conflict-free point;
5. retarget and merge PR #7;
6. retarget and merge the Phase 4 Draft PR;
7. tag the exact aggregate Chatwoot SHA and record the image digest.

## Future deployment and publication order (do not execute now)

1. back up PostgreSQL and record the current image digest;
2. verify all four account flags and all three Central controls are off;
3. build the reviewed Chatwoot image;
4. apply migrations in order;
5. start web and workers from the same image;
6. smoke-test existing Chatwoot behavior with every new flag off;
7. only after the AntiGravity blocker is resolved, publish reviewed V2 and
   record both old/new version IDs and JSON hashes;
8. enable Phase 1 only for the internal account and test queue transition;
9. enable Phase 2 only for the internal account and prove no immediate reply;
10. send one newly-created internal incoming message and prove generation/CAS;
11. enable Phase 3 internally and compare list length with canonical counts;
12. enable Phase 4 shadow internally and enqueue one bounded scan;
13. observe before gradual expansion.

## Copyable smoke checklist

- [ ] Login and open an existing internal conversation.
- [ ] Incoming and outgoing messages still work before feature activation.
- [ ] Assignment, labels, private note, resolve, and reopen still work.
- [ ] ActionCable updates arrive once and do not regress generation.
- [ ] Phase 1 double click creates one transition and one note.
- [ ] Stale message, assignee, and generation return HTTP 409.
- [ ] Queue state is open, unassigned, `aguardando-humano`, not `bot-bia`.
- [ ] Phase 2 creates no public message immediately.
- [ ] Phase 2 private note, label, and attribute events are ignored by Bia.
- [ ] A new internal incoming message exceeds the resume boundary.
- [ ] CAS reset applies once; replay is duplicate; stale generation is blocked.
- [ ] Guarded sender creates one message; replay creates none.
- [ ] Financeiro, multiple contracts/invoices, Pix, boleto, and fallback are mocked or internal-only.
- [ ] Support, ONU, Radius, registration, transfer, media, sticker, timeout, and fallback remain guarded.
- [ ] `mine`, `human_queue`, and `bia` lists are mutually exclusive.
- [ ] Canonical counters equal canonical list queries on desktop and mobile.
- [ ] Counter/list errors show retry and never false zero or infinite loading.
- [ ] Phase 4 report contains aggregates only and no conversation/customer data.
- [ ] Central paths are off and no Incident HTTP node is reached.
- [ ] Web, Sidekiq, PostgreSQL, Redis, EvolutionAPI, and n8n logs are healthy.

## Observability

Monitor transition and Bia-session reason codes, duplicate/replay/conflict
counts, CAS 409 rates, public-message uniqueness, ActionCable ordering,
canonical list/count divergence, Sidekiq failures, database lock waits, and
Phase 4 classification distributions. Logs must not contain message bodies,
documents, phone numbers, payment data, or credentials.

## Rollback

### Chatwoot

1. turn all four flags off;
2. stop manual Phase 4 enqueueing;
3. revert web/workers to the recorded image together;
4. keep additive schema and audit rows;
5. do not execute destructive down migrations after live use.

### AntiGravity

1. stop further activation steps and drain in-flight executions;
2. restore active version `4ec83b46-b85c-4413-85cd-c33e7588f9f3`;
3. confirm public senders and Central-off controls;
4. preserve V1/V2 drafts, backup JSON, hashes, and sanitized logs.

Phase 3 rolls back by disabling its flag. Phase 4 rolls back by disabling its
flag and stopping the shadow job; it has no conversation mutations to undo.

## Residual blockers

- Guarded Chatwoot sender V1 is text-only; strict attachment/template senders
  cannot silently fall back to direct delivery.
- EvolutionAPI, SGP, Radius, liberation, registration, and other external APIs
  cannot share a database transaction with Chatwoot. Each irreversible path
  needs immediate generation validation, deterministic provider idempotency or
  a claimed operation ledger, and explicit residual-risk approval.
- The AntiGravity V2 structural validator retains documented pre-existing
  workflow warnings. Any effect path that bypasses session guards blocks
  publication.
- The n8n API's current/active version now differs from the recorded stable
  baseline `4ec83b46-b85c-4413-85cd-c33e7588f9f3`; establish the actual
  published graph and its hash before any release action.

Until these blockers are resolved and CI is fully reviewed, the correct final
decision is **keep every flag off and do not publish the draft**.
