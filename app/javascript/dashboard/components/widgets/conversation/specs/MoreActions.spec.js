/* eslint-disable vue/one-component-per-file -- local component doubles keep this interaction test isolated */
import { defineComponent, h, nextTick } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import MoreActions from '../MoreActions.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';

const mocks = vi.hoisted(() => ({
  currentChat: {},
  dispatch: vi.fn(),
  alert: vi.fn(),
  featureEnabled: true,
  permitted: true,
  confirmed: true,
}));

vi.mock('vuex', () => ({
  useStore: () => ({
    getters: { getSelectedChat: mocks.currentChat },
    dispatch: mocks.dispatch,
  }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    checkPermissions: () => mocks.permitted,
    isFeatureFlagEnabled: () => mocks.featureEnabled,
  }),
}));
vi.mock('widget/helpers/uuid', () => ({ default: () => 'uuid-12345678' }));
vi.mock('shared/helpers/mitt', () => ({
  emitter: { on: vi.fn(), off: vi.fn() },
}));
vi.mock('@vueuse/core', async importOriginal => {
  const actual = await importOriginal();
  const { ref } = await import('vue');
  return {
    ...actual,
    useToggle: initialValue => {
      const value = ref(initialValue);
      const toggle = nextValue => {
        value.value = typeof nextValue === 'boolean' ? nextValue : !value.value;
      };
      return [value, toggle];
    },
  };
});

const DropdownStub = defineComponent({
  name: 'DropdownMenu',
  props: { menuItems: { type: Array, default: () => [] } },
  emits: ['action'],
  setup(props, { emit }) {
    return () =>
      h('div', {
        'data-test': 'dropdown',
        'data-items': props.menuItems.length,
        onClick: () => emit('action', {}),
      });
  },
});

const ConfirmModalStub = defineComponent({
  name: 'WootConfirmModal',
  methods: {
    showConfirmation() {
      return Promise.resolve(mocks.confirmed);
    },
  },
  template: '<div data-test="confirmation" />',
});

const mountComponent = () =>
  mount(MoreActions, {
    global: {
      stubs: {
        DropdownMenu: DropdownStub,
        ResolveAction: true,
        EmailTranscriptModal: true,
        'woot-confirm-modal': ConfirmModalStub,
      },
      directives: {
        'on-clickaway': () => {},
      },
      mocks: { $t: key => key },
    },
  });

const openMenu = async wrapper => {
  await wrapper.findComponent(ButtonV4).trigger('click');
  await nextTick();
  return wrapper.findComponent(DropdownStub);
};

describe('MoreActions send to human queue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.currentChat = {
      id: 45,
      status: 'open',
      muted: false,
      labels: ['bot-bia', 'priority-customer'],
      meta: { assignee: { id: 7 } },
      custom_attributes: {},
      last_non_activity_message: { id: 123 },
    };
    mocks.featureEnabled = true;
    mocks.permitted = true;
    mocks.confirmed = true;
    mocks.dispatch.mockResolvedValue({ status: 'accepted' });
  });

  it('shows the action only when feature and permission allow it', async () => {
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    expect(dropdown.props('menuItems')).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ action: 'send_to_human_queue' }),
      ])
    );
  });

  it('keeps the action available in the mobile header layout', async () => {
    Object.defineProperty(window, 'innerWidth', {
      configurable: true,
      value: 375,
    });
    window.dispatchEvent(new Event('resize'));
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    expect(dropdown.props('menuItems')).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ action: 'send_to_human_queue' }),
      ])
    );
  });

  it.each([
    ['feature disabled', false, true],
    ['permission denied', true, false],
  ])('hides the action when %s', async (_reason, feature, permitted) => {
    mocks.featureEnabled = feature;
    mocks.permitted = permitted;
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    expect(dropdown.props('menuItems')).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ action: 'send_to_human_queue' }),
      ])
    );
  });

  it('hides the action when the conversation is already projected to the queue', async () => {
    mocks.currentChat = {
      ...mocks.currentChat,
      labels: ['aguardando-humano', 'priority-customer'],
      meta: {},
      custom_attributes: { bia_retorno_humano_pendente: true },
    };
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    expect(dropdown.props('menuItems')).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ action: 'send_to_human_queue' }),
      ])
    );
  });

  it('does not call the backend when confirmation is cancelled', async () => {
    mocks.confirmed = false;
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    dropdown.vm.$emit('action', { action: 'send_to_human_queue' });
    await flushPromises();

    expect(mocks.dispatch).not.toHaveBeenCalled();
  });

  it('submits one authoritative transition and reports success', async () => {
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    dropdown.vm.$emit('action', { action: 'send_to_human_queue' });
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledTimes(1);
    expect(mocks.dispatch).toHaveBeenCalledWith('sendToHumanQueue', {
      conversationId: 45,
      idempotencyKey: expect.stringMatching(/^queue-\d+-uuid-12345678$/),
      expectedLastMessageId: 123,
      expectedSessionGeneration: 0,
    });
    expect(mocks.alert).toHaveBeenCalledWith(
      'CONVERSATION.SEND_TO_HUMAN_QUEUE.SUCCESS'
    );
  });

  it('ignores activity messages when deriving the concurrency guard', async () => {
    mocks.currentChat = {
      ...mocks.currentChat,
      last_non_activity_message: null,
      messages: [
        { id: 122, message_type: 0 },
        { id: 123, message_type: 2 },
      ],
    };
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    dropdown.vm.$emit('action', { action: 'send_to_human_queue' });
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith(
      'sendToHumanQueue',
      expect.objectContaining({ expectedLastMessageId: 122 })
    );
  });

  it('blocks repeated interaction while the request is pending', async () => {
    let resolveRequest;
    mocks.dispatch.mockReturnValue(
      new Promise(resolve => {
        resolveRequest = resolve;
      })
    );
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    dropdown.vm.$emit('action', { action: 'send_to_human_queue' });
    await flushPromises();

    expect(wrapper.findComponent(ButtonV4).element.disabled).toBe(true);
    expect(wrapper.findComponent(ButtonV4).props('isLoading')).toBe(true);
    expect(mocks.dispatch).toHaveBeenCalledTimes(1);

    resolveRequest({ status: 'accepted' });
    await flushPromises();
  });

  it.each([
    [409, 'CONVERSATION.SEND_TO_HUMAN_QUEUE.CONFLICT'],
    [500, 'CONVERSATION.SEND_TO_HUMAN_QUEUE.ERROR'],
  ])('shows the correct feedback for HTTP %s', async (status, message) => {
    mocks.dispatch.mockRejectedValue({ response: { status } });
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    dropdown.vm.$emit('action', { action: 'send_to_human_queue' });
    await flushPromises();

    expect(mocks.alert).toHaveBeenCalledWith(message);
  });
});

describe('MoreActions return to Bia', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.currentChat = {
      id: 45,
      status: 'open',
      muted: false,
      labels: ['aguardando-humano', 'priority-customer'],
      meta: { assignee: { id: 7 } },
      custom_attributes: {
        bia_retorno_humano_pendente: true,
        bia_automation_state: 'paused_human',
        bia_session_generation: 4,
      },
      last_non_activity_message: { id: 123 },
    };
    mocks.featureEnabled = true;
    mocks.permitted = true;
    mocks.confirmed = true;
    mocks.dispatch.mockResolvedValue({ status: 'accepted' });
  });

  it('shows the action for an authorized human-managed conversation', async () => {
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    expect(dropdown.props('menuItems')).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ action: 'return_to_bia' }),
      ])
    );
  });

  it.each([
    ['feature disabled', false, true],
    ['permission denied', true, false],
  ])('hides the action when %s', async (_reason, feature, permitted) => {
    mocks.featureEnabled = feature;
    mocks.permitted = permitted;
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    expect(dropdown.props('menuItems')).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ action: 'return_to_bia' }),
      ])
    );
  });

  it.each(['resolved', 'pending', 'snoozed'])(
    'hides the action for a %s conversation',
    async status => {
      mocks.currentChat.status = status;
      const wrapper = mountComponent();
      const dropdown = await openMenu(wrapper);

      expect(dropdown.props('menuItems')).not.toEqual(
        expect.arrayContaining([
          expect.objectContaining({ action: 'return_to_bia' }),
        ])
      );
    }
  );

  it('hides the action when the conversation is already in a complete Bia session', async () => {
    mocks.currentChat = {
      ...mocks.currentChat,
      labels: ['bot-bia', 'priority-customer'],
      meta: {},
      custom_attributes: {
        bia_retorno_humano_pendente: false,
        bia_automation_state: 'active',
        bia_session_generation: 5,
      },
    };
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    expect(dropdown.props('menuItems')).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ action: 'return_to_bia' }),
      ])
    );
  });

  it('does not call the backend when confirmation is cancelled', async () => {
    mocks.confirmed = false;
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    dropdown.vm.$emit('action', { action: 'return_to_bia' });
    await flushPromises();

    expect(mocks.dispatch).not.toHaveBeenCalled();
  });

  it('submits one authoritative transition and reports that Bia will wait', async () => {
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    dropdown.vm.$emit('action', { action: 'return_to_bia' });
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledTimes(1);
    expect(mocks.dispatch).toHaveBeenCalledWith('returnToBia', {
      conversationId: 45,
      idempotencyKey: expect.stringMatching(/^bia-\d+-uuid-12345678$/),
      expectedLastMessageId: 123,
      expectedAssigneeId: 7,
      expectedSessionGeneration: 4,
    });
    expect(mocks.alert).toHaveBeenCalledWith(
      'CONVERSATION.RETURN_TO_BIA.SUCCESS'
    );
  });

  it('blocks a second transition while return is pending', async () => {
    let resolveRequest;
    mocks.dispatch.mockReturnValue(
      new Promise(resolve => {
        resolveRequest = resolve;
      })
    );
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    dropdown.vm.$emit('action', { action: 'return_to_bia' });
    dropdown.vm.$emit('action', { action: 'return_to_bia' });
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledTimes(1);
    expect(wrapper.findComponent(ButtonV4).props('isLoading')).toBe(true);

    resolveRequest({ status: 'accepted' });
    await flushPromises();
  });

  it.each([
    [409, 'CONVERSATION.RETURN_TO_BIA.CONFLICT'],
    [500, 'CONVERSATION.RETURN_TO_BIA.ERROR'],
  ])('shows the correct feedback for HTTP %s', async (status, message) => {
    mocks.dispatch.mockRejectedValue({ response: { status } });
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    dropdown.vm.$emit('action', { action: 'return_to_bia' });
    await flushPromises();

    expect(mocks.alert).toHaveBeenCalledWith(message);
  });

  it('keeps the return action available in the mobile header layout', async () => {
    Object.defineProperty(window, 'innerWidth', {
      configurable: true,
      value: 375,
    });
    window.dispatchEvent(new Event('resize'));
    const wrapper = mountComponent();
    const dropdown = await openMenu(wrapper);

    expect(dropdown.props('menuItems')).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ action: 'return_to_bia' }),
      ])
    );
  });
});
