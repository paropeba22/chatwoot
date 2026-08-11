# Chatwoot Phase 3: canonical operational tabs and realtime ordering

## Scope and rollout

This phase is stacked on the Bia atomic-session gate. It does not change a conversation while the account feature `conversation_operational_buckets` is disabled. The boolean account flag defaults to `false`, outside the saturated legacy feature bitmap.

## Canonical projection

`Conversations::OperationalBucket` is the shared authority for list scopes, counts, and serialized projection metadata. Precedence is deliberately fail-safe:

1. an open conversation assigned to the current human is `mine`;
2. an open unassigned conversation carrying `aguardando-humano` is `human_queue`;
3. an open unassigned conversation carrying `bot-bia`, without `aguardando-humano`, is `bia` when a strict session is active or when no session contract exists;
4. every other state is unclassified.

Contradictory historical states are assigned to only the safest applicable bucket and returned with `operational_bucket_inconsistent=true`; this phase does not mutate or reconcile them.

The query parameter `operational_bucket=mine|human_queue|bia` applies the same SQL scopes used by `meta.operational_buckets`. Native AgentBot assignments are explicit and are not treated as unassigned.

## Frontend consistency

When the flag is enabled, `ChatList` requests the canonical bucket and consumes one backend counter projection instead of subtracting independent requests. Realtime objects are filtered by `operational_bucket`, preventing cross-tab bleed.

List requests carry a monotonically increasing local sequence. Responses and errors from an older request cannot terminate loading or replace a newer tab. Equal-timestamp realtime events retain the higher `bia_session_generation`, using the protection introduced by Phase 2. Counter failures retain the last known values and display a recoverable retry instead of a false zero.

## Migration and activation

Migration `20260806000001` adds only `accounts.conversation_operational_buckets_enabled boolean NOT NULL DEFAULT false`.

Future controlled rollout:

1. deploy code and run the additive migration with the flag off;
2. validate legacy tabs;
3. enable the flag for the internal account only;
4. compare each list length with `meta.operational_buckets`;
5. test Phase 1 and Phase 2 transitions and out-of-order realtime events;
6. disable the flag immediately if lists, counters, or loading diverge.

Schema rollback is safe before activation. After activation, prefer disabling the flag and retaining the additive column.

## Residual scope

Advanced filters and saved folders keep their existing semantics. Historical inconsistent conversations are reported but not repaired. A shadow reconciliation report may consume the inconsistency marker later; no automatic correction belongs to this phase.
