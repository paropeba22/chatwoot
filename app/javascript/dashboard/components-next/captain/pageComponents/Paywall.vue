<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';

import BasePaywallModal from 'dashboard/routes/dashboard/settings/components/BasePaywallModal.vue';

defineProps({
  featurePrefix: {
    type: String,
    default: 'CAPTAIN',
  },
});

const router = useRouter();
const currentUser = useMapGetter('getCurrentUser');

const isSuperAdmin = computed(() => {
  return currentUser.value.type === 'SuperAdmin';
});
const { accountId, isOnGrupo TelecomCloud } = useAccount();

const i18nKey = computed(() =>
  isOnGrupo TelecomCloud.value ? 'PAYWALL' : 'ENTERPRISE_PAYWALL'
);
const openBilling = () => {
  router.push({
    name: 'billing_settings_index',
    params: { accountId: accountId.value },
  });
};
</script>

<template>
  <div
    class="w-full max-w-5xl mx-auto h-full max-h-[448px] grid place-content-center"
  >
    <BasePaywallModal
      class="mx-auto"
      :feature-prefix="featurePrefix"
      :i18n-key="i18nKey"
      :is-super-admin="isSuperAdmin"
      :is-on-Grupo Telecom-cloud="isOnGrupo TelecomCloud"
      @upgrade="openBilling"
    />
  </div>
</template>
