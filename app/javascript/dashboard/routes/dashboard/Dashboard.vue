<script>
import { defineAsyncComponent, ref, computed, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

import NextSidebar from 'next/sidebar/Sidebar.vue';
import WootKeyShortcutModal from 'dashboard/components/widgets/modal/WootKeyShortcutModal.vue';
import AddAccountModal from 'dashboard/components/app/AddAccountModal.vue';
import UpgradePage from 'dashboard/routes/dashboard/upgrade/UpgradePage.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { useWindowSize } from '@vueuse/core';

import wootConstants from 'dashboard/constants/globals';

const CommandBar = defineAsyncComponent(
  () => import('./commands/commandbar.vue')
);

const FloatingCallWidget = defineAsyncComponent(
  () => import('dashboard/components/widgets/FloatingCallWidget.vue')
);

import CopilotLauncher from 'dashboard/components-next/copilot/CopilotLauncher.vue';
import CopilotContainer from 'dashboard/components/copilot/CopilotContainer.vue';

import MobileSidebarLauncher from 'dashboard/components-next/sidebar/MobileSidebarLauncher.vue';
import { useCallsStore } from 'dashboard/stores/calls';

export default {
  components: {
    NextSidebar,
    CommandBar,
    WootKeyShortcutModal,
    AddAccountModal,
    UpgradePage,
    CopilotLauncher,
    CopilotContainer,
    FloatingCallWidget,
    MobileSidebarLauncher,
  },
  setup() {
    const upgradePageRef = ref(null);
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();
    const { width: windowWidth } = useWindowSize();
    const callsStore = useCallsStore();

    const currentUser = useMapGetter('getCurrentUser');
    const isAgent = computed(() => currentUser.value?.role === 'agent');
    // Agents start in focus mode (sidebar hidden), admins start with sidebar open
    const isFocusMode = ref(false);

    // Initialize focus mode based on role once user data loads
    watch(isAgent, (val) => {
      if (val) isFocusMode.value = true;
    }, { immediate: true });

    const toggleFocusMode = () => {
      isFocusMode.value = !isFocusMode.value;
    };

    return {
      uiSettings,
      updateUISettings,
      accountId,
      upgradePageRef,
      windowWidth,
      hasActiveCall: computed(() => callsStore.hasActiveCall),
      hasIncomingCall: computed(() => callsStore.hasIncomingCall),
      isFocusMode,
      toggleFocusMode,
    };
  },
  data() {
    return {
      showAccountModal: false,
      showCreateAccountModal: false,
      showShortcutModal: false,
      isMobileSidebarOpen: false,
    };
  },
  computed: {
    isSmallScreen() {
      return this.windowWidth < wootConstants.SMALL_SCREEN_BREAKPOINT;
    },
    showUpgradePage() {
      return this.upgradePageRef?.shouldShowUpgradePage;
    },
    bypassUpgradePage() {
      return [
        'billing_settings_index',
        'settings_inbox_list',
        'general_settings_index',
        'agent_list',
      ].includes(this.$route.name);
    },
    previouslyUsedDisplayType() {
      const {
        previously_used_conversation_display_type: conversationDisplayType,
      } = this.uiSettings;
      return conversationDisplayType;
    },
  },
  watch: {
    isSmallScreen: {
      handler() {
        const { LAYOUT_TYPES } = wootConstants;
        if (window.innerWidth <= wootConstants.SMALL_SCREEN_BREAKPOINT) {
          this.updateUISettings({
            conversation_display_type: LAYOUT_TYPES.EXPANDED,
          });
        } else {
          this.updateUISettings({
            conversation_display_type: this.previouslyUsedDisplayType,
          });
        }
      },
      immediate: true,
    },
  },
  methods: {
    toggleMobileSidebar() {
      this.isMobileSidebarOpen = !this.isMobileSidebarOpen;
    },
    closeMobileSidebar() {
      this.isMobileSidebarOpen = false;
    },
    openCreateAccountModal() {
      this.showAccountModal = false;
      this.showCreateAccountModal = true;
    },
    closeCreateAccountModal() {
      this.showCreateAccountModal = false;
    },
    toggleAccountModal() {
      this.showAccountModal = !this.showAccountModal;
    },
    toggleKeyShortcutModal() {
      this.showShortcutModal = true;
    },
    closeKeyShortcutModal() {
      this.showShortcutModal = false;
    },
  },
};
</script>

<template>
  <div class="flex flex-grow overflow-hidden text-n-slate-12 relative">
    <Transition name="sidebar-slide">
      <NextSidebar
        v-if="!isFocusMode"
        :is-mobile-sidebar-open="isMobileSidebarOpen"
        @toggle-account-modal="toggleAccountModal"
        @open-key-shortcut-modal="toggleKeyShortcutModal"
        @close-key-shortcut-modal="closeKeyShortcutModal"
        @show-create-account-modal="openCreateAccountModal"
        @close-mobile-sidebar="closeMobileSidebar"
      />
    </Transition>

    <main
      class="flex flex-1 h-full w-full min-h-0 px-0 overflow-hidden bg-n-surface-1 transition-all duration-300 ease-in-out"
    >
      <button
        class="fixed bottom-6 right-6 z-50 rounded-2xl px-5 py-2.5 shadow-lg hover:shadow-xl transition-all duration-300 ease-in-out font-medium text-sm text-white"
        style="background: radial-gradient(circle at 30% 50%, #1a3a6e 0%, #0a1628 100%); border: 1px solid rgba(0, 82, 255, 0.25);"
        @click="toggleFocusMode"
      >
        <span
          v-if="isFocusMode"
          class="i-lucide-layout-panel-left size-4 inline-block align-text-bottom mr-1"
        />
        <span
          v-else
          class="i-lucide-maximize size-4 inline-block align-text-bottom mr-1"
        />
        {{ isFocusMode ? 'Voltar à Gestão' : 'Atendimento Focado' }}
      </button>

      <UpgradePage
        v-show="showUpgradePage"
        ref="upgradePageRef"
        :bypass-upgrade-page="bypassUpgradePage"
      >
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
      </UpgradePage>
      <template v-if="!showUpgradePage">
        <router-view />
        <CommandBar />
        <CopilotLauncher />
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
        <CopilotContainer />
        <FloatingCallWidget v-if="hasActiveCall || hasIncomingCall" />
      </template>
      <AddAccountModal
        :show="showCreateAccountModal"
        @close-account-create-modal="closeCreateAccountModal"
      />
      <WootKeyShortcutModal
        v-model:show="showShortcutModal"
        @close="closeKeyShortcutModal"
        @clickaway="closeKeyShortcutModal"
      />
    </main>
  </div>
</template>

<style scoped>
.sidebar-slide-enter-active,
.sidebar-slide-leave-active {
  transition: transform 0.3s ease-in-out, opacity 0.3s ease-in-out;
}
.sidebar-slide-enter-from,
.sidebar-slide-leave-to {
  transform: translateX(-100%);
  opacity: 0;
}
</style>
