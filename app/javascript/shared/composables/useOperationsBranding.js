import { computed } from 'vue';
import { useStore } from 'vuex';

export const DEFAULT_OPERATIONS_BRANDING = Object.freeze({
  providerName: 'Grupo Telecom',
  logo: '/brand-assets/logo_dark.png',
  logoThumbnail: '/brand-assets/logo_thumbnail.png',
  consoleTitle: 'ISP Operations Console',
  statusText: 'Operação online',
  aiDisplayName: 'Bia',
});

const configuredValue = (value, fallback) =>
  typeof value === 'string' && value.trim() ? value.trim() : fallback;

const configuredBrandAsset = (value, chatwootDefault, fallback) => {
  const configured = configuredValue(value, chatwootDefault);
  return configured === chatwootDefault ? fallback : configured;
};

export const resolveOperationsBranding = (globalConfig = {}) => {
  const installationName = configuredValue(
    globalConfig.installationName,
    'Chatwoot'
  );
  const useGrupoTelecomFallback = installationName === 'Chatwoot';

  return {
    providerName: useGrupoTelecomFallback
      ? DEFAULT_OPERATIONS_BRANDING.providerName
      : installationName,
    logo: useGrupoTelecomFallback
      ? DEFAULT_OPERATIONS_BRANDING.logo
      : configuredBrandAsset(
          globalConfig.logoDark,
          '/brand-assets/logo_dark.svg',
          DEFAULT_OPERATIONS_BRANDING.logo
        ),
    logoThumbnail: useGrupoTelecomFallback
      ? DEFAULT_OPERATIONS_BRANDING.logoThumbnail
      : configuredBrandAsset(
          globalConfig.logoThumbnail,
          '/brand-assets/logo_thumbnail.svg',
          DEFAULT_OPERATIONS_BRANDING.logoThumbnail
        ),
    consoleTitle: configuredValue(
      globalConfig.operationsConsoleTitle,
      DEFAULT_OPERATIONS_BRANDING.consoleTitle
    ),
    statusText: configuredValue(
      globalConfig.operationsStatusText,
      DEFAULT_OPERATIONS_BRANDING.statusText
    ),
    aiDisplayName: configuredValue(
      globalConfig.operationsAiDisplayName,
      DEFAULT_OPERATIONS_BRANDING.aiDisplayName
    ),
  };
};

export const useOperationsBranding = () => {
  const store = useStore();
  return computed(() =>
    resolveOperationsBranding(store.getters['globalConfig/get'])
  );
};
