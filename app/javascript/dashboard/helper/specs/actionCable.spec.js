import { describe, it, beforeEach, expect, vi } from 'vitest';
import ActionCableConnector from '../actionCable';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    emit: vi.fn(),
  },
}));

vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({
    isImpersonating: { value: false },
  }),
}));

global.chatwootConfig = {
  websocketURL: 'wss://test.chatwoot.com',
};

describe('ActionCableConnector', () => {
  let store;
  let actionCable;
  let mockDispatch;
  let featureEnabled;

  beforeEach(() => {
    vi.clearAllMocks();
    mockDispatch = vi.fn();
    featureEnabled = vi.fn(() => false);
    store = {
      $store: {
        dispatch: mockDispatch,
        getters: {
          getCurrentAccountId: 1,
          'accounts/isFeatureEnabledonAccount': featureEnabled,
        },
      },
    };

    actionCable = ActionCableConnector.init(store.$store, 'test-token');
  });
  describe('copilot event handlers', () => {
    it('should register the copilot.message.created event handler', () => {
      expect(Object.keys(actionCable.events)).toContain(
        'copilot.message.created'
      );
      expect(actionCable.events['copilot.message.created']).toBe(
        actionCable.onCopilotMessageCreated
      );
    });

    it('should handle the copilot.message.created event through the ActionCable system', () => {
      const copilotData = {
        id: 2,
        content: 'This is a copilot message from ActionCable',
        conversation_id: 456,
        created_at: '2025-05-27T15:58:04-06:00',
        account_id: 1,
      };
      actionCable.onReceived({
        event: 'copilot.message.created',
        data: copilotData,
      });
      expect(mockDispatch).toHaveBeenCalledWith(
        'copilotMessages/upsert',
        copilotData
      );
    });
  });

  describe('canonical operational bucket events', () => {
    const conversation = {
      id: 42,
      account_id: 1,
      operational_bucket: 'bia',
    };

    it('reloads the authoritative projection after an assignee change', () => {
      featureEnabled.mockReturnValue(true);

      actionCable.onAssigneeChanged(conversation);

      expect(featureEnabled).toHaveBeenCalledWith(
        1,
        FEATURE_FLAGS.CONVERSATION_OPERATIONAL_BUCKETS
      );
      expect(mockDispatch).toHaveBeenCalledWith('getConversation', 42);
      expect(mockDispatch).not.toHaveBeenCalledWith(
        'updateConversation',
        conversation
      );
    });

    it('reloads the authoritative projection for conversation updates', () => {
      featureEnabled.mockReturnValue(true);

      actionCable.onConversationUpdated(conversation);

      expect(mockDispatch).toHaveBeenCalledWith('getConversation', 42);
    });

    it('loads new conversations with their authoritative projection', () => {
      featureEnabled.mockReturnValue(true);

      actionCable.onConversationCreated(conversation);

      expect(mockDispatch).toHaveBeenCalledWith('getConversation', 42);
      expect(mockDispatch).not.toHaveBeenCalledWith(
        'addConversation',
        conversation
      );
    });

    it('preserves the legacy realtime path when the account flag is off', () => {
      actionCable.onAssigneeChanged(conversation);

      expect(mockDispatch).toHaveBeenCalledWith(
        'updateConversation',
        conversation
      );
      expect(mockDispatch).not.toHaveBeenCalledWith('getConversation', 42);
    });
  });
});
