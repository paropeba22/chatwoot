import { buildConversationRouteLocation } from '../conversationRouteHelper';

describe('conversationRouteHelper', () => {
  it('keeps queue view as router query when opening a conversation', () => {
    expect(
      buildConversationRouteLocation({
        accountId: 1,
        id: 478,
        view: 'unassigned',
      })
    ).toEqual({
      path: '/app/accounts/1/conversations/478',
      query: { view: 'unassigned' },
    });
  });

  it('keeps bot view and resolved status as router query', () => {
    expect(
      buildConversationRouteLocation({
        accountId: 1,
        id: 479,
        view: 'bot',
        status: 'resolved',
      })
    ).toEqual({
      path: '/app/accounts/1/conversations/479',
      query: { view: 'bot', status: 'resolved' },
    });
  });

  it('keeps inbox-specific conversation paths intact', () => {
    expect(
      buildConversationRouteLocation({
        accountId: 1,
        activeInbox: 5,
        id: 480,
        view: 'unassigned',
      })
    ).toEqual({
      path: '/app/accounts/1/inbox/5/conversations/480',
      query: { view: 'unassigned' },
    });
  });
});
