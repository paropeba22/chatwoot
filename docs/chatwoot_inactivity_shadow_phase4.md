# Chatwoot Phase 4: inactivity classification in shadow mode

## Safety boundary

Phase 4 is observation-only. The account feature
`conversation_inactivity_shadow` is a dedicated boolean column with default
`false`. No scheduler is enabled by this change. The job never sends messages,
changes conversations, labels, assignment, status, custom attributes, or Bia
session state.

## Classifier

`Conversations::InactivityShadowClassifier` combines the canonical Phase 3
bucket with public-message direction, delivery status, session generation,
context reset, handoff, and operational flags. It produces one of:

- `waiting_customer`;
- `waiting_human`;
- `waiting_automation`;
- `likely_completed`;
- `operation_pending`;
- `handoff_pending`;
- `stale_inconsistent`;
- `do_not_touch`;
- `unknown`.

Two independent clocks are recorded: seconds since the most recent public
outgoing message (customer wait) and seconds since the most recent public
incoming message (operation/company wait). `updated_at` is not used as an
inactivity decision by itself. Resolved, pending, snoozed, contradictory,
reset-pending, handoff, and undelivered-message states are protected from a
false abandoned-customer classification.

The `likely_completed` category requires an explicit stable completion signal;
elapsed time alone is insufficient.

## Job and persistence

`Conversations::InactivityShadowJob` scans one account in bounded ID-ordered
batches of 200. A PostgreSQL account-scoped advisory lock prevents two workers
from scanning the same account concurrently. Each conversation is upserted to
one small assessment row. The row contains identifiers, category, reason,
canonical bucket, generation, two durations, confidence, and observation time;
it contains no message content, phone, document, payment data, or credentials.

No recurring schedule is installed. During a future controlled rollout an
operator may enqueue the job only after enabling the account flag. The next
batch is scheduled only when the previous batch was full.

## Aggregate report

Administrators can read the aggregate-only endpoint:

`GET /api/v1/accounts/:account_id/conversation_inactivity_shadow`

The response groups count, maximum clock values, and average confidence by
classification, bucket, and reason. Conversation IDs and customer data are not
returned. The endpoint is hidden with HTTP 404 while the feature is disabled;
non-administrators are rejected by backend authorization.

## Migration and rollback

Migration `20260807000001` adds the disabled account flag and the assessment
table with foreign keys, checks, and reporting/uniqueness indexes. PostgreSQL
16 up/down/up is mandatory before release. The production rollback is to keep
the flag off (or turn it off) and stop enqueuing the job. Because shadow mode
does not mutate conversations, no conversation reconciliation is required.

## Validation

Focused specs cover the two clocks, delivery pending, context reset, queue,
human ownership, closed conversations, malformed generation, feature-off job,
advisory-lock contention, aggregate authorization, and the integrated
Bia → queue → Bia → new incoming → CAS reset lifecycle. CI also runs the
up/down/up migration, changed-file RuboCop, Gitleaks, and emits a generated
schema artifact.

## Residual limitations

This is a conservative classifier, not an automated decision system. Unknown
business state stays `unknown` or `operation_pending`. Automatic resolution,
customer messaging, transfer, and remediation require a later separately
authorized phase based on observed shadow precision.
