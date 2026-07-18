import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Form from '../pages/Form.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn().mockResolvedValue({ id: 1 }),
  push: vi.fn(),
  alert: vi.fn(),
}));

vi.mock('vuex', () => ({
  useStore: () => ({
    dispatch: mocks.dispatch,
    getters: {
      'technicalIncidents/getTechnicalIncidentOptions': {
        incident_types: ['unplanned_outage'],
        severities: ['minor'],
        problem_types: ['internet_connectivity'],
        service_keys: ['internet'],
        actions: ['message_and_handoff'],
        scope_types: ['general', 'contract_id'],
        template_variables: [
          'estimated_resolution_at',
          'affected_service',
          'incident_title',
        ],
      },
      'technicalIncidents/getTechnicalIncidentUIFlags': { saving: false },
    },
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: {} }),
  useRouter: () => ({ push: mocks.push }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/composables', () => ({
  useAlert: mocks.alert,
}));

describe('Technical Incidents form', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders the literal preview as escaped text', async () => {
    const wrapper = shallowMount(Form, {
      global: { stubs: { RouterLink: true } },
    });
    await flushPromises();

    const message = wrapper.find('textarea[maxlength="4000"]');
    await message.setValue('<script>alert(1)</script>');

    expect(wrapper.html()).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
    expect(wrapper.html()).not.toContain('<script>alert(1)</script>');
  });

  it('blocks an unknown template variable before calling create', async () => {
    const wrapper = shallowMount(Form, {
      global: { stubs: { RouterLink: true } },
    });
    await flushPromises();
    mocks.dispatch.mockClear();

    await wrapper
      .find('textarea[maxlength="4000"]')
      .setValue('Prazo: {{invented_deadline}}');
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
    const wrapper = shallowMount(Form, {
      global: { stubs: { RouterLink: true } },
    });
    await flushPromises();
    mocks.dispatch.mockRejectedValueOnce({ response: { status: 409 } });

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.text()).toContain('TECHNICAL_INCIDENTS.FORM.CONFLICT');
    expect(mocks.alert).toHaveBeenCalledWith(
      'TECHNICAL_INCIDENTS.FORM.CONFLICT'
    );
    expect(mocks.push).not.toHaveBeenCalled();
  });
});
