import wootConstants from 'dashboard/constants/globals';
import {
  buildConversationFilterQuery,
  normalizeAssigneeView,
  normalizeConversationStatus,
} from '../conversationFilterQueryHelper';

describe('conversationFilterQueryHelper', () => {
  describe('#normalizeAssigneeView', () => {
    it('keeps queue, bot, and all views', () => {
      expect(normalizeAssigneeView('unassigned')).toBe('unassigned');
      expect(normalizeAssigneeView('bot')).toBe('bot');
      expect(normalizeAssigneeView('all')).toBe('all');
    });

    it('falls back to my conversations for unknown views', () => {
      expect(normalizeAssigneeView('invalid')).toBe(
        wootConstants.ASSIGNEE_TYPE.ME
      );
    });
  });

  describe('#normalizeConversationStatus', () => {
    it('keeps supported conversation statuses', () => {
      expect(normalizeConversationStatus('resolved')).toBe('resolved');
      expect(normalizeConversationStatus('snoozed')).toBe('snoozed');
    });

    it('returns null for unknown statuses', () => {
      expect(normalizeConversationStatus('archived')).toBeNull();
    });
  });

  describe('#buildConversationFilterQuery', () => {
    it('preserves the bot tab and resolved status', () => {
      expect(
        buildConversationFilterQuery({ view: 'bot', status: 'resolved' })
      ).toEqual({ view: 'bot', status: 'resolved' });
    });

    it('keeps the all view for finalized history', () => {
      expect(
        buildConversationFilterQuery({ view: 'all', status: 'resolved' })
      ).toEqual({ view: 'all', status: 'resolved' });
    });

    it('omits default open status from the URL query', () => {
      expect(
        buildConversationFilterQuery({ view: 'me', status: 'open' })
      ).toEqual({ view: 'me' });
    });
  });
});
