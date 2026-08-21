import { mount } from '@vue/test-utils';
import ChatTypeTabs from '../ChatTypeTabs.vue';

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

const items = [
  { key: 'me', name: 'Mine', count: 4 },
  { key: 'unassigned', name: 'Queue', count: 2 },
  { key: 'all', name: 'Bia', count: 7 },
];

describe('ChatTypeTabs', () => {
  it('renders all three operational tabs without carousel controls', () => {
    const wrapper = mount(ChatTypeTabs, {
      props: { items, activeTab: 'me' },
      global: {
        stubs: {
          'woot-tabs': {
            props: ['index', 'showScrollButtons'],
            template:
              '<div data-testid="tabs" :data-scroll-buttons="showScrollButtons"><slot /></div>',
          },
          'woot-tabs-item': {
            props: ['name', 'count'],
            template: '<button>{{ name }} {{ count }}</button>',
          },
        },
      },
    });

    expect(wrapper.get('[data-testid="tabs"]').text()).toContain('Mine 4');
    expect(wrapper.get('[data-testid="tabs"]').text()).toContain('Queue 2');
    expect(wrapper.get('[data-testid="tabs"]').text()).toContain('Bia 7');
    expect(wrapper.findAll('button')).toHaveLength(3);
    expect(
      wrapper.get('[data-testid="tabs"]').attributes('data-scroll-buttons')
    ).toBe('false');
    expect(wrapper.get('[data-testid="tabs"]').classes()).toEqual(
      expect.arrayContaining([
        'min-w-0',
        'max-w-full',
        'overflow-x-auto',
        '[&_ul]:min-w-0',
        '[&_ul]:max-w-full',
        '[&_ul]:overflow-x-auto',
        '[&_ul]:md:grid',
        '[&_ul]:md:grid-cols-3',
      ])
    );
    expect(wrapper.get('[data-testid="tabs"]').classes()).not.toContain(
      '[&_ul]:min-w-max'
    );
  });
});
