import wootConstants from 'dashboard/constants/globals';

export const BOT_ASSIGNEE_VIEW = 'bot';

const VALID_ASSIGNEE_VIEWS = [
  wootConstants.ASSIGNEE_TYPE.ME,
  wootConstants.ASSIGNEE_TYPE.UNASSIGNED,
  wootConstants.ASSIGNEE_TYPE.ALL,
  BOT_ASSIGNEE_VIEW,
];

const VALID_STATUS_FILTERS = Object.values(wootConstants.STATUS_TYPE);

export const normalizeAssigneeView = (
  view,
  fallback = wootConstants.ASSIGNEE_TYPE.ME
) => {
  const normalizedView = String(view || '');
  return VALID_ASSIGNEE_VIEWS.includes(normalizedView)
    ? normalizedView
    : fallback;
};

export const normalizeConversationStatus = status => {
  const normalizedStatus = String(status || '');
  return VALID_STATUS_FILTERS.includes(normalizedStatus)
    ? normalizedStatus
    : null;
};

export const resolveAssigneeViewForStatus = (view, status) =>
  status === wootConstants.STATUS_TYPE.RESOLVED
    ? wootConstants.ASSIGNEE_TYPE.ALL
    : normalizeAssigneeView(view, wootConstants.ASSIGNEE_TYPE.ME);

export const buildConversationFilterQuery = ({ view, status } = {}) => {
  const query = {};
  const normalizedView = normalizeAssigneeView(view, null);
  const normalizedStatus = normalizeConversationStatus(status);

  if (normalizedView) {
    query.view = normalizedView;
  }

  if (normalizedStatus && normalizedStatus !== wootConstants.STATUS_TYPE.OPEN) {
    query.status = normalizedStatus;
  }

  return Object.keys(query).length ? query : undefined;
};
