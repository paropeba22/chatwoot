import {
  getInboxChipLabel,
  getInboxDisplayIcon,
  getInboxDisplayName,
  getInboxShortName,
  isGrupoTelecomInbox,
} from '../inboxPresentationHelper';

describe('inboxPresentationHelper', () => {
  it('uses branded display values for Grupo Telecom API inboxes', () => {
    const inbox = { name: 'grupotelecom', channel_type: 'Channel::Api' };

    expect(isGrupoTelecomInbox(inbox)).toBe(true);
    expect(getInboxDisplayName(inbox)).toBe('Grupo Telecom');
    expect(getInboxShortName(inbox)).toBe('Grupo Telecom');
    expect(getInboxChipLabel(inbox)).toBe('WhatsApp - Grupo Telecom');
    expect(getInboxDisplayIcon(inbox)).toBe('i-woot-whatsapp');
  });

  it('uses official display values for the official inbox', () => {
    const inbox = {
      name: 'grupotelecomoficial',
      channelType: 'Channel::Api',
    };

    expect(isGrupoTelecomInbox(inbox)).toBe(true);
    expect(getInboxDisplayName(inbox)).toBe('Grupo Telecom Oficial');
    expect(getInboxShortName(inbox)).toBe('Oficial');
    expect(getInboxChipLabel(inbox)).toBe('WhatsApp - Oficial');
  });

  it('keeps ordinary API inboxes unchanged', () => {
    const inbox = { name: 'external-api', channel_type: 'Channel::Api' };

    expect(isGrupoTelecomInbox(inbox)).toBe(false);
    expect(getInboxDisplayName(inbox)).toBe('external-api');
    expect(getInboxChipLabel(inbox)).toBe('external-api');
    expect(getInboxDisplayIcon(inbox)).toBeNull();
  });
});
