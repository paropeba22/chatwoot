import {
  isOnMentionsView,
  isOnFoldersView,
  isOnParticipatingView,
  buildConversationList,
} from '../actionHelpers';
import types from '../../../../mutation-types';

describe('#isOnMentionsView', () => {
  it('return valid responses when passing the state', () => {
    expect(isOnMentionsView({ route: { name: 'conversation_mentions' } })).toBe(
      true
    );
    expect(isOnMentionsView({ route: { name: 'conversation_messages' } })).toBe(
      false
    );
  });
});

describe('#isOnFoldersView', () => {
  it('return valid responses when passing the state', () => {
    expect(isOnFoldersView({ route: { name: 'folder_conversations' } })).toBe(
      true
    );
    expect(
      isOnFoldersView({ route: { name: 'conversations_through_folders' } })
    ).toBe(true);
    expect(isOnFoldersView({ route: { name: 'conversation_messages' } })).toBe(
      false
    );
  });
});

describe('#isOnParticipatingView', () => {
  it('return valid responses when passing the state', () => {
    expect(
      isOnParticipatingView({ route: { name: 'conversation_participating' } })
    ).toBe(true);
    expect(
      isOnParticipatingView({
        route: { name: 'conversation_through_participating' },
      })
    ).toBe(true);
    expect(
      isOnParticipatingView({ route: { name: 'conversation_messages' } })
    ).toBe(false);
  });
});

describe('#buildConversationList', () => {
  const commit = vi.fn();
  const dispatch = vi.fn();

  beforeEach(() => {
    commit.mockClear();
    dispatch.mockClear();
  });

  it('does not overwrite tab stats when list is filtered by bot-bia label', () => {
    buildConversationList(
      { commit, dispatch },
      { page: 1, labels: ['bot-bia'] },
      { payload: [{ id: 1 }], meta: { mine_count: 2, unassigned_count: 0 } },
      'all'
    );

    expect(commit).toHaveBeenCalledWith(types.SET_ALL_CONVERSATION, [
      { id: 1 },
    ]);
    expect(dispatch).not.toHaveBeenCalledWith(
      'conversationStats/set',
      expect.anything()
    );
  });

  it('keeps syncing stats for normal non-filtered list fetches', () => {
    buildConversationList(
      { commit, dispatch },
      { page: 1 },
      { payload: [{ id: 2 }], meta: { mine_count: 4, unassigned_count: 7 } },
      'me'
    );

    expect(dispatch).toHaveBeenCalledWith('conversationStats/set', {
      mine_count: 4,
      unassigned_count: 7,
    });
  });
});
