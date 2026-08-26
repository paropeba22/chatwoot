import { computed } from 'vue';
import { shallowMount } from '@vue/test-utils';
import OperationalStatus from '../OperationalStatus.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, { aiName } = {}) =>
      key.endsWith('.BIA') ? `Com IA · ${aiName}` : key.split('.').at(-1),
  }),
}));

vi.mock('shared/composables/useOperationsBranding', () => ({
  useOperationsBranding: () => computed(() => ({ aiDisplayName: 'Bia' })),
}));

describe('OperationalStatus', () => {
  it.each([
    ['human', 'i-lucide-headset'],
    ['bia', 'i-lucide-bot'],
    ['queue', 'i-lucide-clock-3'],
    ['resolved', 'i-lucide-circle-check-big'],
    ['neutral', 'i-lucide-circle-dot-dashed'],
  ])('renders the %s presentation state', (state, icon) => {
    const wrapper = shallowMount(OperationalStatus, { props: { state } });

    expect(wrapper.attributes('data-state')).toBe(state);
    expect(wrapper.classes()).toContain(`gt-operational-status--${state}`);
    expect(wrapper.find(`.${icon}`).exists()).toBe(true);
  });

  it('uses the configured AI display name', () => {
    const wrapper = shallowMount(OperationalStatus, {
      props: { state: 'bia' },
    });

    expect(wrapper.text()).toContain('Com IA · Bia');
  });

  it('falls back to a neutral presentation for unknown states', () => {
    const wrapper = shallowMount(OperationalStatus, {
      props: { state: 'unexpected' },
    });

    expect(wrapper.attributes('data-state')).toBe('neutral');
    expect(wrapper.classes()).toContain('gt-operational-status--neutral');
  });
});
