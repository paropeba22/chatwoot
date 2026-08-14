import { shallowMount } from '@vue/test-utils';
import ConversationHeader from '../ConversationHeader.vue';

const mocks = vi.hoisted(() => ({
  currentChat: { id: 42, status: 'open' },
}));

vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({
    getters: {
      getSelectedChat: mocks.currentChat,
      getCurrentAccountId: 1,
      'contacts/getContact': () => ({
        name: 'Internal test',
        thumbnail: '',
        availability_status: 'online',
      }),
      'inboxes/getInbox': () => ({ id: 1 }),
      'inboxes/getInboxes': [],
    },
  }),
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: {}, query: {}, name: 'home' }),
}));
vi.mock('@vueuse/core', () => ({
  useElementSize: () => ({ width: 1024 }),
}));
vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () => ({ isAWebWidgetInbox: { value: false } }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('ConversationHeader', () => {
  it('places conversation actions above message content without changing the shared dropdown', () => {
    const wrapper = shallowMount(ConversationHeader, {
      props: {
        chat: {
          inbox_id: 1,
          meta: { sender: { id: 7 } },
        },
      },
      global: { mocks: { $t: key => key } },
    });

    const header = wrapper.get('.gt-conversation-header');
    expect(header.classes()).toEqual(
      expect.arrayContaining(['relative', 'z-30', 'overflow-visible'])
    );
    expect(wrapper.findComponent({ name: 'MoreActions' }).exists()).toBe(true);
  });
});
