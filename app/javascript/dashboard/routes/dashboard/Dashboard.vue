<script>
import { defineAsyncComponent, ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';

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

// Captain/Copilot AI removido — IA externa via n8n

import MobileSidebarLauncher from 'dashboard/components-next/sidebar/MobileSidebarLauncher.vue';
import { useCallsStore } from 'dashboard/stores/calls';

export default {
  components: {
    NextSidebar,
    CommandBar,
    WootKeyShortcutModal,
    AddAccountModal,
    UpgradePage,
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
      // Broadcast to children (e.g. ChatListHeader) so they can mirror the state
      emitter.emit('focus-mode-changed', isFocusMode.value);
    };

    // Allow ChatListHeader (and others) to request a toggle without prop drilling
    const onToggleRequest = () => toggleFocusMode();

    onMounted(() => {
      emitter.on('toggle-focus-mode', onToggleRequest);
    });

    onUnmounted(() => {
      emitter.off('toggle-focus-mode', onToggleRequest);
    });

    return {
      uiSettings,
      updateUISettings,
      accountId,
      upgradePageRef,
      windowWidth,
      hasActiveCall: computed(() => callsStore.hasActiveCall),
      hasIncomingCall: computed(() => callsStore.hasIncomingCall),
      isFocusMode,
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
    <div
      class="flex-shrink-0 transition-all duration-300 ease-in-out overflow-hidden"
      :style="{ width: isFocusMode ? '0px' : undefined, minWidth: isFocusMode ? '0px' : undefined }"
    >
      <NextSidebar
        v-show="!isFocusMode"
        :is-mobile-sidebar-open="isMobileSidebarOpen"
        @toggle-account-modal="toggleAccountModal"
        @open-key-shortcut-modal="toggleKeyShortcutModal"
        @close-key-shortcut-modal="closeKeyShortcutModal"
        @show-create-account-modal="openCreateAccountModal"
        @close-mobile-sidebar="closeMobileSidebar"
      />
    </div>

    <main
      class="flex flex-1 h-full w-full min-h-0 px-0 overflow-hidden bg-n-surface-1 transition-all duration-300 ease-in-out"
    >
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
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
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
