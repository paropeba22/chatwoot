/* eslint-disable vue/one-component-per-file */
import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import ChatTypeTabs from '../ChatTypeTabs.vue';

const useKeyboardEventsMock = vi.hoisted(() => vi.fn());

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: useKeyboardEventsMock,
}));

const items = [
  { key: 'me', name: 'Mine', count: 4 },
  { key: 'unassigned', name: 'Queue', count: 2 },
  { key: 'bot', name: 'AI', count: 7 },
  { key: 'all', name: 'All', count: 13 },
];

const WootTabsStub = defineComponent({
  name: 'WootTabs',
  props: {
    index: { type: Number, default: 0 },
    showScrollButtons: { type: Boolean, default: true },
  },
  emits: ['change'],
  setup(props, { emit, slots }) {
    return () =>
      h(
        'div',
        {
          'data-testid': 'tabs',
          'data-index': props.index,
          'data-scroll-buttons': props.showScrollButtons,
          onClick: event => emit('change', Number(event.target.dataset.index)),
        },
        slots.default?.()
      );
  },
});

const WootTabsItemStub = defineComponent({
  name: 'WootTabsItem',
  props: {
    name: { type: String, required: true },
    count: { type: Number, required: true },
    index: { type: Number, required: true },
  },
  setup(props) {
    return () =>
      h(
        'button',
        { 'data-index': props.index },
        `${props.name} ${props.count}`
      );
  },
});

const mountComponent = (props = {}) =>
  mount(ChatTypeTabs, {
    props: { items, activeTab: 'me', ...props },
    global: {
      stubs: {
        'woot-tabs': WootTabsStub,
        'woot-tabs-item': WootTabsItemStub,
      },
    },
  });

describe('ChatTypeTabs', () => {
  beforeEach(() => {
    useKeyboardEventsMock.mockClear();
  });

  it('renders the four operational tabs in order without carousel controls', () => {
    const wrapper = mountComponent();

    expect(wrapper.findAll('button').map(button => button.text())).toEqual([
      'Mine 4',
      'Queue 2',
      'AI 7',
      'All 13',
    ]);
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
        '[&_ul]:md:grid-cols-4',
      ])
    );
    expect(wrapper.get('[data-testid="tabs"]').classes()).not.toContain(
      '[&_ul]:min-w-max'
    );
  });

  it('emits the distinct bot and all view keys', async () => {
    const wrapper = mountComponent();
    const tabs = wrapper.findAll('button');

    await tabs[2].trigger('click');
    await tabs[3].trigger('click');

    expect(wrapper.emitted('chatTabChange')).toEqual([['bot'], ['all']]);
  });

  it('cycles through all four views with Alt+N', async () => {
    const wrapper = mountComponent();
    const keyboardEvents = useKeyboardEventsMock.mock.calls[0][0];

    keyboardEvents['Alt+KeyN'].action();
    await wrapper.setProps({ activeTab: 'unassigned' });
    keyboardEvents['Alt+KeyN'].action();
    await wrapper.setProps({ activeTab: 'bot' });
    keyboardEvents['Alt+KeyN'].action();
    await wrapper.setProps({ activeTab: 'all' });
    keyboardEvents['Alt+KeyN'].action();

    expect(wrapper.emitted('chatTabChange')).toEqual([
      ['unassigned'],
      ['bot'],
      ['all'],
      ['me'],
    ]);
  });
});
