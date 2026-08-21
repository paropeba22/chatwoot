import {
  getConversationSignal,
  visibleConversationLabels,
} from '../conversationSignal';

describe('conversationSignal', () => {
  it.each([
    [{ operational_bucket: 'mine' }, 'human'],
    [{ operational_bucket: 'human_queue' }, 'queue'],
    [{ operational_bucket: 'bia' }, 'bia'],
  ])(
    'maps a canonical operational bucket to its visual signal',
    (chat, signal) => {
      expect(getConversationSignal(chat)).toBe(signal);
    }
  );

  it.each([null, undefined, 'unexpected'])(
    'keeps an explicit non-canonical bucket neutral: %s',
    operationalBucket => {
      expect(
        getConversationSignal({
          operational_bucket: operationalBucket,
          status: 'open',
          labels: ['bot-bia'],
        })
      ).toBe('neutral');
    }
  );

  it.each(['resolved', 'pending', 'snoozed'])(
    'keeps %s legacy conversations neutral',
    status => {
      expect(getConversationSignal({ status, labels: ['bot-bia'] })).toBe(
        'neutral'
      );
    }
  );

  it('keeps an AgentBot-assigned legacy conversation neutral', () => {
    expect(
      getConversationSignal({
        status: 'open',
        assignee_agent_bot_id: 9,
        labels: ['bot-bia'],
      })
    ).toBe('neutral');
  });

  it('keeps a paused strict Bia session neutral', () => {
    expect(
      getConversationSignal({
        status: 'open',
        labels: ['bot-bia'],
        custom_attributes: { bia_automation_state: 'paused_human' },
      })
    ).toBe('neutral');
  });

  it('gives human assignment precedence over legacy Bia labels', () => {
    expect(
      getConversationSignal({
        status: 'open',
        meta: { assignee: { id: 7 } },
        labels: ['bot-bia'],
      })
    ).toBe('human');
  });

  it('gives the human queue precedence over legacy Bia labels', () => {
    expect(
      getConversationSignal({
        status: 'open',
        labels: ['aguardando-humano', 'bot-bia'],
      })
    ).toBe('queue');
  });

  it('identifies an active strict legacy Bia conversation', () => {
    expect(
      getConversationSignal({
        status: 'open',
        labels: ['bot-bia'],
        custom_attributes: { bia_automation_state: 'active' },
      })
    ).toBe('bia');
  });

  it('identifies a legacy Bia conversation without strict session state', () => {
    expect(getConversationSignal({ status: 'open', labels: ['bot-bia'] })).toBe(
      'bia'
    );
  });

  it('is null-safe for conversations without labels', () => {
    expect(getConversationSignal({ status: 'open', labels: null })).toBe(
      'neutral'
    );
    expect(getConversationSignal(null)).toBe('neutral');
  });

  it('keeps business labels while hiding internal routing labels', () => {
    expect(
      visibleConversationLabels({
        labels: ['financeiro', 'bot-bia', 'aguardando-humano'],
      })
    ).toEqual(['financeiro']);
  });
});
