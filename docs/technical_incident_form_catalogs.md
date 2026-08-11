# Technical incident form catalogs

## Scope and safety

This change repairs the existing **New incident** form. It does not enable the
account feature, automation, outbox, API Inbox delivery, AntiGravity shadow or
active mode. It does not introduce new matching semantics or read customer/SGP
data to build catalogs.

The existing endpoint remains authoritative:

```text
GET /api/v1/accounts/:account_id/technical_incidents/options
```

It is account-authenticated, feature-gated and authorized for administrators or
Custom Roles that can view, create or update technical incidents.

## Root cause

The database was not missing catalog rows. V1 catalogs are controlled code
allowlists. The broken screen combined four independent defects:

1. `/options` returned arrays of canonical strings without display metadata;
2. native selects omitted the dark-theme text token, so existing options could
   be visually indistinguishable from their background;
3. metadata loading had no loading/error state, and authorization/network errors
   left the initial empty object looking like a successful empty catalog;
4. scope values were deliberately initialized and rendered as JSON text (`[]`),
   requiring operators to edit an internal persistence representation.

There was also a permission mismatch: the create route accepted
`technical_incident_create`, while `/options` required
`technical_incident_view`. A create-only Custom Role could enter the form but
could not load its options.

## Canonical catalog map

| Form field        | Canonical source                             | Persisted format    |
| ----------------- | -------------------------------------------- | ------------------- |
| Incident type     | `TechnicalIncident::INCIDENT_TYPES`          | string              |
| Severity          | `TechnicalIncident::SEVERITIES`              | string              |
| Action            | `TechnicalIncident::ACTIONS`                 | string              |
| Problem types     | `TechnicalIncident::PROBLEM_TYPES`           | string array        |
| Affected services | `TechnicalIncident::SERVICE_KEYS`            | string array        |
| Scope fields      | `TechnicalIncidentScopeCriterion::TYPES`     | string              |
| Scope operators   | `TechnicalIncidentScopeCriterion::OPERATORS` | string (`in` in V1) |
| Scope values      | `ScopeCriterionValuesValidator`              | typed JSONB array   |

No seed or account catalog table is required. An empty required catalog now
means a code/configuration defect and blocks saving with an explicit message.

## Metadata contract

Every catalog entry has a stable value, fallback label and frontend translation
key:

```json
{
  "value": "unplanned_outage",
  "label": "Unplanned outage",
  "label_key": "TECHNICAL_INCIDENTS.CATALOG.INCIDENT_TYPES.UNPLANNED_OUTAGE"
}
```

Scope fields additionally describe the input contract:

```json
{
  "value": "city_neighborhood",
  "allowed_operators": ["in"],
  "value_type": "location_pairs",
  "value_fields": ["city", "neighborhood"],
  "required": true,
  "multiple": true,
  "available_values": []
}
```

The response contains `metadata_version`, `incident_types`, `statuses`,
`severities`, `problem_types`, `affected_services`, `actions`, `scope_fields`,
`scope_operators` and `template_variables`.

## Scope serialization

Groups remain OR branches. Criteria within one group remain AND conditions.
The frontend sends the pre-existing nested contract:

```json
{
  "scope_groups_attributes": [
    {
      "position": 0,
      "criteria_attributes": [
        {
          "criterion_type": "city_neighborhood",
          "operator": "in",
          "values": [{ "city": "Recife", "neighborhood": "Centro" }]
        },
        {
          "criterion_type": "service_specific",
          "operator": "in",
          "values": ["internet"]
        }
      ]
    }
  ]
}
```

The UI uses checkboxes for controlled catalogs, one-value-per-line inputs for
identifiers/CEP and explicit paired fields for city/neighborhood or city/street.
It never exposes JSON syntax. Legacy stringified arrays are normalized when an
existing incident is opened. Unknown legacy values remain visible as warnings
and cannot be saved until corrected.

## Validation

The frontend blocks saving when metadata failed/was empty, required catalogs are
not selected, priority/dates are invalid, a required literal message is absent,
or scope groups/criteria are empty, duplicated or malformed.

The backend remains authoritative. `IncidentValidator` now applies template and
scope invariants to drafts as well as operational incidents. Model validation
also requires affected services and rejects review after expiration or a
restoration estimate before the start time. Operator/type/value allowlists,
maximum duration, strong parameters and account isolation remain in force.

## Action descriptions

- `message_and_handoff`: literal incident message, followed by human handoff;
- `message_only`: literal incident message without handoff;
- `handoff_only`: human handoff without an incident message.

These are descriptions of the existing commit contract. They do not enable it.
All backend automation and delivery switches must remain disabled until their
separate production gates are approved.

## Loading, error and empty states

- loading: “Loading incident options…”;
- request/authorization failure: explicit error plus retry;
- successful but incomplete metadata: explicit unconfigured state;
- out-of-order requests: only the newest metadata response is committed;
- unmounted form: no incident hydration/navigation is performed afterwards.

## Database and compatibility

No migration and no seed are introduced. Persistence types and the V1 matcher
contract are unchanged. Existing valid incidents deserialize to the typed
controls. Legacy unknown/string values are shown but rejected on the next save,
preventing silent corruption.

## Manual rollout

1. Keep `technical_incidents` disabled for production accounts and keep all
   AntiGravity/backend automation switches off.
2. Deploy the reviewed application image; there is no migration step for this
   change.
3. In an isolated account, enable only the UI feature and open New incident.
4. Verify all catalogs, loading/error/retry, both languages and responsive
   layout.
5. Save/reopen a draft in the isolated database and inspect the nested scope
   payload.
6. Confirm no conversation, message, label, handoff or incident delivery was
   produced.
7. Leave AntiGravity and backend automation disabled.

Smoke cases: general; service-specific; contract ID; POP ID; CEP; city/bairro;
city/rua; two criteria in one group; two OR groups; empty group; invalid value;
unknown legacy value; failed `/options`; retry; desktop/mobile/keyboard.

## Rollback

Disable the account feature and deploy the previous application image. No schema
rollback or data deletion is needed. Drafts saved with this version use the same
V1 persistence contract and remain readable by the previous backend, although
the previous UI would again expose JSON scope values.
