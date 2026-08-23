const INTERNAL_OPERATIONAL_LABELS = new Set(['bot-bia', 'aguardando-humano']);
const CANONICAL_SIGNALS = {
  mine: 'human',
  human_queue: 'queue',
  bia: 'bia',
};
const BIA_SESSION_KEYS = ['bia_automation_state', 'bia_session_generation'];

const hasOwnProperty = (object, property) =>
  Object.prototype.hasOwnProperty.call(object ?? {}, property);

const isPresent = value => value !== null && value !== undefined;

const labelNames = conversation =>
  (conversation?.labels || []).map(label =>
    typeof label === 'string' ? label : label?.title
  );

export const getConversationSignal = conversation => {
  if (hasOwnProperty(conversation, 'operational_bucket')) {
    return CANONICAL_SIGNALS[conversation.operational_bucket] || 'neutral';
  }

  if (conversation?.status !== 'open') return 'neutral';

  const labels = labelNames(conversation);
  const hasHumanAssignee =
    isPresent(conversation?.assignee_id) ||
    isPresent(conversation?.meta?.assignee?.id);
  const hasAgentBotAssignee =
    isPresent(conversation?.assignee_agent_bot_id) ||
    Boolean(conversation?.meta?.assignee_agent_bot);

  if (hasHumanAssignee) return 'human';
  if (hasAgentBotAssignee) return 'neutral';

  const isWaitingForHuman = labels.includes('aguardando-humano');
  if (isWaitingForHuman) return 'queue';

  const customAttributes = conversation?.custom_attributes ?? {};
  const hasStrictSessionState = BIA_SESSION_KEYS.some(key =>
    hasOwnProperty(customAttributes, key)
  );

  if (
    labels.includes('bot-bia') &&
    (!hasStrictSessionState ||
      customAttributes.bia_automation_state === 'active')
  ) {
    return 'bia';
  }

  return 'neutral';
};

export const getConversationPresentationSignal = conversation =>
  conversation?.status === 'resolved'
    ? 'resolved'
    : getConversationSignal(conversation);

export const visibleConversationLabels = conversation =>
  (conversation?.labels || []).filter(label => {
    const name = typeof label === 'string' ? label : label?.title;
    return !INTERNAL_OPERATIONAL_LABELS.has(name);
  });
