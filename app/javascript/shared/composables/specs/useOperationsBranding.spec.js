import {
  DEFAULT_OPERATIONS_BRANDING,
  resolveOperationsBranding,
} from '../useOperationsBranding';

describe('resolveOperationsBranding', () => {
  it('preserves the Grupo Telecom branding when config is absent', () => {
    expect(resolveOperationsBranding()).toEqual(DEFAULT_OPERATIONS_BRANDING);
  });

  it('supports another provider without changing application code', () => {
    expect(
      resolveOperationsBranding({
        installationName: 'Fibra Exemplo',
        logoDark: '/branding/fibra-exemplo.svg',
        logoThumbnail: '/branding/fibra-exemplo-icon.svg',
        operationsConsoleTitle: 'Central Fibra',
        operationsStatusText: 'Rede online',
        operationsAiDisplayName: 'Lia',
      })
    ).toEqual({
      providerName: 'Fibra Exemplo',
      logo: '/branding/fibra-exemplo.svg',
      logoThumbnail: '/branding/fibra-exemplo-icon.svg',
      consoleTitle: 'Central Fibra',
      statusText: 'Rede online',
      aiDisplayName: 'Lia',
    });
  });

  it('falls back per field for blank configuration values', () => {
    expect(
      resolveOperationsBranding({
        installationName: 'Chatwoot',
        operationsAiDisplayName: null,
      })
    ).toEqual(DEFAULT_OPERATIONS_BRANDING);
  });

  it('does not expose upstream Chatwoot assets in the Grupo fallback', () => {
    expect(
      resolveOperationsBranding({
        installationName: 'Grupo Telecom',
        logoDark: '/brand-assets/logo_dark.svg',
        logoThumbnail: '/brand-assets/logo_thumbnail.svg',
      })
    ).toMatchObject({
      logo: '/brand-assets/logo_dark.png',
      logoThumbnail: '/brand-assets/logo_thumbnail.png',
    });
  });
});
