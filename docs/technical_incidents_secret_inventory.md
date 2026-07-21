# Sanitized secret inventory

No value is reproduced here.

Tracked Chatwoot repository scan: no detected private key, provider key,
GitHub token, OpenAI-style key or hardcoded automation token.

Live AntiGravity read-only inventory:

| Node | Type |
| --- | --- |
| `Resolver_Evolution_Instance` | provider API key stored in Code/config rather than an n8n credential |

Historical local exports outside this Git worktree contain the same API-key
type and must not be committed:

- `workflow_details_after_app_ascii_expr.json`
- `workflow_details_after_app_direct_tool.json`
- `workflow_details_after_encoding_absolute_final.json`
- `workflow_details_after_encoding_final_verify.json`
- `workflow_details_after_encoding_fix.json`
- `workflow_details_after_encoding_fix_ascii.json`
- `workflow_details_after_encoding_repair_full.json`
- `workflow_details_after_encoding_replace_true.json`
- `workflow_details_after_evolution_patch.json`
- `workflow_details_before_encoding_fix.json`
- `workflow_details_current_ai_errors.json`
- `workflow_details_current_encoding_bug.json`
- `workflow_details_final_evolution_patch.json`
- `workflow_details_raw.json`

Code mitigation: the Chatwoot integration reads only environment switches and
uses the existing encrypted AgentBot access-token mechanism. The readiness CI
scans complete Git history with Gitleaks.

Production mitigation still pending: create replacement provider credentials,
move them to the n8n credential store/secret manager, update a new draft, test,
publish with separate authorization, then revoke the old values. Historical
exports must be securely deleted or encrypted after the operator confirms they
are no longer required.
