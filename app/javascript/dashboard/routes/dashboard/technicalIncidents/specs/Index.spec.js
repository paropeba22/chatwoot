import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Index from '../pages/Index.vue';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn().mockResolvedValue({}),
  push: vi.fn(),
  canCreate: true,
}));

vi.mock('vuex', () => ({
  useStore: () => ({
    dispatch: mocks.dispatch,
    getters: {
      'technicalIncidents/getTechnicalIncidents': [
        {
          id: 1,
          title: '<img src=x onerror=alert(1)>',
          incident_type: 'unplanned_outage',
          status: 'active',
          severity: 'major',
          affected_services: ['internet'],
          estimated_resolution_at: null,
          conversation_links_count: 0,
        },
      ],
      'technicalIncidents/getTechnicalIncidentMeta': {
        total_entries: 1,
        per_page: 25,
      },
      'technicalIncidents/getTechnicalIncidentOptions': {
        statuses: [],
        severities: [],
        incident_types: [],
        scope_types: [],
      },
      'technicalIncidents/getTechnicalIncidentUIFlags': {
        fetching: false,
      },
    },
  }),
}));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: mocks.push }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    checkPermissions: () => mocks.canCreate,
  }),
}));

describe('Technical Incidents index', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.canCreate = true;
  });

  it('loads options and records and renders technician text as escaped text', async () => {
    const wrapper = shallowMount(Index, {
      global: {
        stubs: { RouterLink: true },
      },
    });
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith(
      'technicalIncidents/fetchOptions'
    );
    expect(mocks.dispatch).toHaveBeenCalledWith(
      'technicalIncidents/fetch',
      expect.any(Object)
    );
    expect(wrapper.html()).toContain('&lt;img src=x onerror=alert(1)&gt;');
    expect(wrapper.html()).not.toContain('<img src="x"');
  });

  it('hides the create action without permission', async () => {
    mocks.canCreate = false;
    const wrapper = shallowMount(Index, {
      global: {
        stubs: { RouterLink: true },
      },
    });
    await flushPromises();

    expect(wrapper.findComponent({ name: 'RouterLink' }).exists()).toBe(false);
  });
});
