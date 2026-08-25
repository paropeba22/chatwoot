import wootConstants from 'dashboard/constants/globals';
import {
  buildConversationFilterQuery,
  normalizeAssigneeView,
  normalizeConversationStatus,
  resolveAssigneeViewForStatus,
  resolveConversationFilterState,
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
    it.each(['bot', 'me', 'unassigned', 'all'])(
      'canonicalizes the %s view to all for finalized history',
      view => {
        expect(
          buildConversationFilterQuery({ view, status: 'resolved' })
        ).toEqual({ view: 'all', status: 'resolved' });
      }
    );

    it('keeps an already canonical resolved query unchanged', () => {
      const canonicalQuery = buildConversationFilterQuery({
        view: 'bot',
        status: 'resolved',
      });

      expect(buildConversationFilterQuery(canonicalQuery)).toEqual(
        canonicalQuery
      );
    });

    it.each(['bot', 'me', 'unassigned', 'all'])(
      'preserves the explicit %s view for open conversations',
      view => {
        expect(buildConversationFilterQuery({ view, status: 'open' })).toEqual({
          view,
        });
      }
    );
  });

  describe('#resolveAssigneeViewForStatus', () => {
    it('forces finalized history to the authorized all view', () => {
      expect(resolveAssigneeViewForStatus('me', 'resolved')).toBe('all');
      expect(resolveAssigneeViewForStatus('bot', 'resolved')).toBe('all');
    });

    it('keeps operational views strict for open conversations', () => {
      expect(resolveAssigneeViewForStatus('me', 'open')).toBe('me');
      expect(resolveAssigneeViewForStatus('bot', 'open')).toBe('bot');
    });
  });

  describe('#resolveConversationFilterState', () => {
    it('keeps an explicitly requested all view on open and hard refresh', () => {
      expect(
        resolveConversationFilterState({ view: 'all', status: 'open' })
      ).toEqual({ view: 'all', status: 'open' });
    });

    it('defaults an open URL without a view to mine', () => {
      expect(resolveConversationFilterState({ status: 'open' })).toEqual({
        view: 'me',
        status: 'open',
      });
    });

    it('forces resolved to all and permits an explicit me after reopening', () => {
      expect(
        resolveConversationFilterState({ view: 'bot', status: 'resolved' })
      ).toEqual({ view: 'all', status: 'resolved' });
      expect(
        resolveConversationFilterState({ view: 'me', status: 'open' })
      ).toEqual({ view: 'me', status: 'open' });
    });
  });
});
