import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Form from '../pages/Form.vue';

const option = (value, label, extras = {}) => ({
  value,
  label,
  label_key: `catalog.${value}`,
  ...extras,
});
const completeMetadata = () => ({
  metadata_version: 1,
  incident_types: [option('unplanned_outage', 'Unplanned outage')],
  statuses: [option('draft', 'Draft')],
  severities: [option('minor', 'Minor')],
  problem_types: [
    option('internet_connectivity', 'Internet connectivity'),
    option('dns', 'DNS'),
  ],
  affected_services: [option('internet', 'Internet'), option('dns', 'DNS')],
  actions: [
    option('message_and_handoff', 'Send message and hand off', {
      description_key: 'action.message_and_handoff',
    }),
    option('handoff_only', 'Hand off only', {
      description_key: 'action.handoff_only',
    }),
  ],
  scope_fields: [
    option('general', 'General', {
      allowed_operators: ['in'],
      value_type: 'none',
      required: false,
      multiple: false,
      available_values: [],
    }),
    option('contract_id', 'Contract ID', {
      allowed_operators: ['in'],
      value_type: 'string_list',
      required: true,
      multiple: true,
      available_values: [],
    }),
  ],
  scope_operators: [option('in', 'Matches any listed value')],
  template_variables: [
    'estimated_resolution_at',
    'affected_service',
    'incident_title',
  ],
});

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  push: vi.fn(),
  alert: vi.fn(),
  metadata: {},
  uiFlags: {},
  routeParams: {},
}));

vi.mock('vuex', () => ({
  useStore: () => ({
    dispatch: mocks.dispatch,
    getters: {
      get 'technicalIncidents/getTechnicalIncidentOptions'() {
        return mocks.metadata;
      },
      get 'technicalIncidents/getTechnicalIncidentUIFlags'() {
        return mocks.uiFlags;
      },
    },
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: mocks.routeParams }),
  useRouter: () => ({ push: mocks.push }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, fallback) => fallback || key,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));

const mountForm = () =>
  mount(Form, { global: { stubs: { RouterLink: true } } });
const completeRequiredFields = async wrapper => {
  await wrapper.find('input[maxlength="200"]').setValue('Incident');
  await wrapper
    .find('textarea[maxlength="4000"]')
    .setValue('Literal customer message');
};

describe('Technical Incidents form', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.metadata = completeMetadata();
    mocks.routeParams = {};
    mocks.uiFlags = {
      fetchingOptions: false,
      optionsError: null,
      saving: false,
    };
    mocks.dispatch.mockImplementation(action => {
      if (action === 'technicalIncidents/fetchOptions') {
        return Promise.resolve(mocks.metadata);
      }
      return Promise.resolve({ id: 1 });
    });
  });

  it('renders canonical labels with visible text and never exposes raw JSON arrays', async () => {
    const wrapper = mountForm();
    await flushPromises();

    expect(wrapper.text()).toContain('Unplanned outage');
    expect(wrapper.text()).toContain('Internet connectivity');
    expect(wrapper.text()).toContain('General');
    expect(wrapper.text()).not.toContain('[]');
    expect(wrapper.find('select').classes()).toContain('text-n-slate-12');
  });

  it('renders an explicit loading state', () => {
    mocks.uiFlags.fetchingOptions = true;
    const wrapper = mountForm();

    expect(wrapper.text()).toContain(
      'TECHNICAL_INCIDENTS.FORM.LOADING_OPTIONS'
    );
    expect(wrapper.find('form').exists()).toBe(false);
  });

  it('renders an explicit error with one retry action', async () => {
    mocks.uiFlags.optionsError = 500;
    const wrapper = mountForm();
    await flushPromises();
    await wrapper.find('button').trigger('click');

    expect(wrapper.text()).toContain('TECHNICAL_INCIDENTS.FORM.OPTIONS_ERROR');
    expect(mocks.dispatch).toHaveBeenCalledWith(
      'technicalIncidents/fetchOptions'
    );
  });

  it.each(['affected_services', 'scope_operators'])(
    'explains an empty %s catalog and keeps the form unavailable',
    async catalog => {
      mocks.metadata[catalog] = [];
      const wrapper = mountForm();
      await flushPromises();

      expect(wrapper.text()).toContain(
        'TECHNICAL_INCIDENTS.FORM.OPTIONS_EMPTY'
      );
      expect(wrapper.find('form').exists()).toBe(false);
    }
  );

  it('blocks saving until required fields are valid', async () => {
    const wrapper = mountForm();
    await flushPromises();

    expect(wrapper.find('button[type="submit"]').attributes('disabled')).toBe(
      ''
    );
    await wrapper.find('form').trigger('submit');
    expect(mocks.dispatch).not.toHaveBeenCalledWith(
      'technicalIncidents/create',
      expect.anything()
    );
  });

  it('serializes line-based scope values without asking for JSON', async () => {
    const wrapper = mountForm();
    await flushPromises();
    await completeRequiredFields(wrapper);
    await wrapper.find('#scope-0-0-field').setValue('contract_id');
    await wrapper.find('textarea[placeholder]').setValue('CTR-1\nCTR-2');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith(
      'technicalIncidents/create',
      expect.objectContaining({
        scope_groups_attributes: [
          expect.objectContaining({
            criteria_attributes: [
              expect.objectContaining({
                criterion_type: 'contract_id',
                operator: 'in',
                values: ['CTR-1', 'CTR-2'],
              }),
            ],
          }),
        ],
      })
    );
  });

  it('renders the literal preview as escaped text', async () => {
    const wrapper = mountForm();
    await flushPromises();
    await wrapper
      .find('textarea[maxlength="4000"]')
      .setValue('<script>alert(1)</script>');

    expect(wrapper.html()).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
    expect(wrapper.html()).not.toContain('<script>alert(1)</script>');
  });

  it('blocks an unknown template variable before calling create', async () => {
    const wrapper = mountForm();
    await flushPromises();
    await completeRequiredFields(wrapper);
    mocks.dispatch.mockClear();
    await wrapper
      .find('textarea[maxlength="4000"]')
      .setValue('Deadline: {{invented_deadline}}');
    await wrapper.find('form').trigger('submit');

    expect(mocks.dispatch).not.toHaveBeenCalledWith(
      'technicalIncidents/create',
      expect.anything()
    );
    expect(wrapper.text()).toContain(
      'TECHNICAL_INCIDENTS.FORM.UNKNOWN_VARIABLE'
    );
  });

  it('surfaces an optimistic locking conflict without navigating', async () => {
    mocks.dispatch.mockImplementation(action => {
      if (action === 'technicalIncidents/fetchOptions') {
        return Promise.resolve(mocks.metadata);
      }
      const error = new Error('Conflict');
      error.response = { status: 409 };
      return Promise.reject(error);
    });
    const wrapper = mountForm();
    await flushPromises();
    await completeRequiredFields(wrapper);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.text()).toContain('TECHNICAL_INCIDENTS.FORM.CONFLICT');
    expect(mocks.push).not.toHaveBeenCalled();
  });

  it('does not hydrate component state after it is unmounted', async () => {
    let resolveMetadata;
    mocks.dispatch.mockReturnValueOnce(
      new Promise(resolve => {
        resolveMetadata = resolve;
      })
    );
    const wrapper = mountForm();
    wrapper.unmount();
    resolveMetadata(mocks.metadata);
    await flushPromises();

    expect(mocks.push).not.toHaveBeenCalled();
  });

  it('keeps an edit unavailable after a load failure and safely retries legacy nullable fields', async () => {
    mocks.routeParams = { incidentId: '42' };
    let showAttempts = 0;
    mocks.dispatch.mockImplementation(action => {
      if (action === 'technicalIncidents/fetchOptions') {
        return Promise.resolve(mocks.metadata);
      }
      if (action === 'technicalIncidents/show') {
        showAttempts += 1;
        if (showAttempts === 1) return Promise.reject(new Error('Unavailable'));
        return Promise.resolve({
          id: 42,
          title: 'Legacy incident',
          incident_type: 'unplanned_outage',
          severity: 'minor',
          priority: 50,
          problem_types: ['internet_connectivity'],
          affected_services: ['internet'],
          action: 'handoff_only',
          customer_message: null,
          internal_note: null,
          scope_groups: [
            {
              id: 1,
              position: 0,
              criteria: [
                {
                  id: 2,
                  criterion_type: 'general',
                  operator: 'in',
                  values: [],
                },
              ],
            },
          ],
        });
      }
      return Promise.resolve({ id: 42 });
    });

    const wrapper = mountForm();
    await flushPromises();
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'TECHNICAL_INCIDENTS.FORM.INCIDENT_LOAD_ERROR'
    );

    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('form').exists()).toBe(true);
    expect(wrapper.find('input[maxlength="200"]').element.value).toBe(
      'Legacy incident'
    );
    expect(wrapper.find('textarea[maxlength="4000"]').element.value).toBe('');
  });

  it('uses the same responsive and accessible controls on mobile and desktop', async () => {
    const wrapper = mountForm();
    await flushPromises();

    expect(wrapper.find('section').classes()).toContain('md:grid-cols-2');
    expect(wrapper.findAll('fieldset')).toHaveLength(2);
    expect(wrapper.findAll('legend')).toHaveLength(2);
    expect(wrapper.find('#scope-0-0-field').attributes('id')).toBe(
      'scope-0-0-field'
    );
  });
});
