# AntiGravity V1 contract comparison

Read-only source:

- workflow: `8k30Q8FFwvr3lbtu`
- draft: `4b2c8033-1c6f-485f-8770-4ceea73fe0e6`
- published version preserved: `8d433990-e41f-471b-bf32-b8aaed588db7`
- nodes present: `TI_API_Contract_V1`, `TI_Precheck_Adapter_V1`,
  `TI_Match_Adapter_V1`, `TI_Commit_Adapter_V1`,
  `TI_Feedback_Adapter_V1`

The available MCP workflow read operation exposed node names and graph
connections but not Code node source/parameters. The comparison below is
therefore based on the previously approved V1 fixtures and must be confirmed
against a redacted Code export before production.

| Area | Chatwoot V1 | Required adapter confirmation |
| --- | --- | --- |
| version | `contract_version: "1.0"` | exact string |
| precheck path | `/api/v1/technical_incident_checks/precheck` | base URL join and `/api/v1` prefix |
| match path | `/api/v1/technical_incident_checks/:id/match` | opaque ID alias used |
| commit path | `/api/v1/technical_incident_checks/:id/commit` | empty body |
| feedback path | `/api/v1/technical_incident_evaluations/:id/feedback` | feedback field and optional note |
| identifier aliases | `id`, `check_id`, `evaluation_id`, `commit_token` | chosen alias |
| no match | `no_candidate` | any internal `no_match` must normalize to `no_candidate` |
| modes | `shadow`, `active`; server may reduce to disabled/shadow | adapter must accept server fallback |
| precheck required | conversation display ID, source message ID, mode, request ID, version, classification | exact casing/types |
| match required | contracts; selection only when multiple | maximum 20 and sanitized fields |
| commit response | `accepted`, `duplicate`, or `stale` plus reason and delivery metadata | aliases/unknown fields handling |
| timeouts | server fallback/stale, no customer claim | adapter retry/fallback branch |

Pending production gate: export the five node Codes redacted, calculate a
SHA-256 for each, compare every required/optional field and status, then store
only the hashes and this updated table in Git. Do not store credentials or the
unredacted workflow export.
