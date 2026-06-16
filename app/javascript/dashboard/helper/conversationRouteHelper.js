import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { buildConversationFilterQuery } from 'dashboard/helper/conversationFilterQueryHelper';

export const buildConversationRouteLocation = ({
  accountId,
  activeInbox,
  id,
  label,
  teamId,
  conversationType,
  foldersId,
  view,
  status,
}) => ({
  path: frontendURL(
    conversationUrl({
      accountId,
      activeInbox,
      id,
      label,
      teamId,
      conversationType,
      foldersId,
    })
  ),
  query: buildConversationFilterQuery({ view, status }) || {},
});
