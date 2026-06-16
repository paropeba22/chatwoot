const GRUPO_TELECOM_INBOXES = {
  grupotelecom: {
    displayName: 'Grupo Telecom',
    shortName: 'Grupo Telecom',
    chipLabel: 'WhatsApp - Grupo Telecom',
  },
  grupotelecomoficial: {
    displayName: 'Grupo Telecom Oficial',
    shortName: 'Oficial',
    chipLabel: 'WhatsApp - Oficial',
  },
};

const normalizeInboxName = name =>
  String(name || '')
    .trim()
    .toLowerCase();

export const getGrupoTelecomInboxPresentation = inbox => {
  const normalizedName = normalizeInboxName(inbox?.name);
  return GRUPO_TELECOM_INBOXES[normalizedName] || null;
};

export const isGrupoTelecomInbox = inbox => {
  const channelType = inbox?.channel_type || inbox?.channelType;

  return (
    channelType === 'Channel::Api' && !!getGrupoTelecomInboxPresentation(inbox)
  );
};

export const getInboxDisplayName = inbox => {
  return getGrupoTelecomInboxPresentation(inbox)?.displayName || inbox?.name;
};

export const getInboxShortName = inbox => {
  return getGrupoTelecomInboxPresentation(inbox)?.shortName || inbox?.name;
};

export const getInboxChipLabel = inbox => {
  return getGrupoTelecomInboxPresentation(inbox)?.chipLabel || inbox?.name;
};

export const getInboxDisplayIcon = inbox => {
  return isGrupoTelecomInbox(inbox) ? 'i-woot-whatsapp' : null;
};
