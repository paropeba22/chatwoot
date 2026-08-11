import { describe, expect, it } from 'vitest';
import {
  createScopeGroup,
  hydrateScopeGroups,
  serializeScopeGroups,
  validateIncidentForm,
} from '../helpers/formCatalog';

const option = (value, extras = {}) => ({ value, label: value, ...extras });
const metadata = {
  incident_types: [option('unplanned_outage')],
  severities: [option('major')],
  actions: [option('message_and_handoff')],
  problem_types: [option('internet_connectivity')],
  affected_services: [option('internet')],
  scope_fields: [
    option('general', {
      value_type: 'none',
      allowed_operators: ['in'],
      available_values: [],
    }),
    option('city_neighborhood', {
      value_type: 'location_pairs',
      value_fields: ['city', 'neighborhood'],
      allowed_operators: ['in'],
      available_values: [],
    }),
  ],
};
const validForm = () => ({
  title: 'Incident',
  incident_type: 'unplanned_outage',
  severity: 'major',
  priority: 50,
  action: 'message_and_handoff',
  problem_types: ['internet_connectivity'],
  affected_services: ['internet'],
  customer_message: 'Literal message',
  starts_at: '2026-08-04T10:00',
  expires_at: '2026-08-04T16:00',
  review_at: '2026-08-04T12:00',
  scope_groups_attributes: [createScopeGroup(0)],
});

describe('technical incident form catalog helpers', () => {
  it('accepts AND criteria inside groups and OR between groups', () => {
    const form = validForm();
    form.scope_groups_attributes[0].criteria_attributes.push({
      criterion_type: 'city_neighborhood',
      operator: 'in',
      values: [{ city: 'Recife', neighborhood: 'Coqueiral' }],
    });
    form.scope_groups_attributes.push(createScopeGroup(1));

    expect(validateIncidentForm(form, metadata)).toEqual([]);
  });

  it('rejects an empty group, incomplete pair and duplicate field', () => {
    const form = validForm();
    form.scope_groups_attributes[0].criteria_attributes = [];
    form.scope_groups_attributes.push({
      position: 1,
      criteria_attributes: [
        {
          criterion_type: 'city_neighborhood',
          operator: 'in',
          values: [{ city: 'Recife', neighborhood: '' }],
        },
        {
          criterion_type: 'city_neighborhood',
          operator: 'in',
          values: [{ city: 'Recife', neighborhood: 'Centro' }],
        },
      ],
    });

    expect(validateIncidentForm(form, metadata)).toEqual(
      expect.arrayContaining([
        'SCOPE_CRITERION_REQUIRED',
        'DUPLICATE_SCOPE_FIELD',
        'SCOPE_VALUE_REQUIRED',
      ])
    );
  });

  it('normalizes legacy JSON strings without rendering or persisting them as strings', () => {
    const groups = hydrateScopeGroups([
      {
        id: 1,
        position: 0,
        criteria: [
          {
            id: 2,
            criterion_type: 'city_neighborhood',
            operator: 'in',
            values: '[{"city":"Recife","neighborhood":"Centro"}]',
          },
        ],
      },
    ]);

    expect(groups[0].criteria_attributes[0].values).toEqual([
      { city: 'Recife', neighborhood: 'Centro' },
    ]);
    expect(
      serializeScopeGroups(groups)[0].criteria_attributes[0].values
    ).toEqual([{ city: 'Recife', neighborhood: 'Centro' }]);
  });

  it('rejects invalid dates and missing mandatory catalogs', () => {
    const form = validForm();
    form.expires_at = '2026-08-04T09:00';
    form.problem_types = [];
    form.affected_services = [];

    expect(validateIncidentForm(form, metadata)).toEqual(
      expect.arrayContaining([
        'INVALID_EXPIRATION',
        'PROBLEM_TYPES_REQUIRED',
        'SERVICES_REQUIRED',
      ])
    );
  });
});
