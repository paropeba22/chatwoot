<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import getUuid from 'widget/helpers/uuid';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

// No props needed as we're getting currentChat from the store directly
const store = useStore();
const { t } = useI18n();
const { checkPermissions, isFeatureFlagEnabled } = usePolicy();

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);
const [showActionsDropdown, toggleDropdown] = useToggle(false);
const confirmSendToQueueDialog = ref(null);
const confirmReturnToBiaDialog = ref(null);
const isSendingToQueue = ref(false);
const isReturningToBia = ref(false);

const currentChat = computed(() => store.getters.getSelectedChat);
const labels = computed(() => currentChat.value?.labels || []);

const isAlreadyInHumanQueue = computed(() => {
  return (
    currentChat.value?.status === 'open' &&
    !currentChat.value?.meta?.assignee &&
    !labels.value.includes('bot-bia') &&
    labels.value.includes('aguardando-humano') &&
    currentChat.value?.custom_attributes?.bia_retorno_humano_pendente === true
  );
});

const isAlreadyWithBia = computed(() => {
  const attributes = currentChat.value?.custom_attributes || {};
  return (
    currentChat.value?.status === 'open' &&
    !currentChat.value?.meta?.assignee &&
    !currentChat.value?.meta?.assignee_agent_bot &&
    labels.value.includes('bot-bia') &&
    !labels.value.includes('aguardando-humano') &&
    attributes.bia_automation_state === 'active' &&
    Number(attributes.bia_session_generation || 0) > 0 &&
    attributes.bia_retorno_humano_pendente === false
  );
});

const isHumanManagedConversation = computed(() => {
  const attributes = currentChat.value?.custom_attributes || {};
  return (
    labels.value.includes('aguardando-humano') ||
    Boolean(currentChat.value?.meta?.assignee) ||
    attributes.bia_retorno_humano_pendente === true ||
    attributes.bia_automation_state === 'paused_human'
  );
});

const isAutomationTransitioning = computed(
  () => isSendingToQueue.value || isReturningToBia.value
);

const canSendToHumanQueue = computed(() => {
  return (
    isFeatureFlagEnabled(FEATURE_FLAGS.CONVERSATION_SEND_TO_HUMAN_QUEUE) &&
    checkPermissions([
      'administrator',
      'agent',
      'conversation_send_to_queue',
    ]) &&
    Boolean(currentChat.value?.id) &&
    !isAlreadyInHumanQueue.value
  );
});

const canReturnToBia = computed(() => {
  return (
    isFeatureFlagEnabled(FEATURE_FLAGS.CONVERSATION_RETURN_TO_BIA) &&
    checkPermissions(['administrator', 'conversation_return_to_ai']) &&
    Boolean(currentChat.value?.id) &&
    currentChat.value?.status === 'open' &&
    isHumanManagedConversation.value &&
    !isAlreadyWithBia.value
  );
});

const actionMenuItems = computed(() => {
  const items = [];

  if (canSendToHumanQueue.value) {
    items.push({
      icon: 'i-lucide-users',
      label: t('CONVERSATION.SEND_TO_HUMAN_QUEUE.ACTION'),
      action: 'send_to_human_queue',
      value: 'send_to_human_queue',
      disabled: isSendingToQueue.value,
    });
  }

  if (canReturnToBia.value) {
    items.push({
      icon: 'i-lucide-bot',
      label: t('CONVERSATION.RETURN_TO_BIA.ACTION'),
      action: 'return_to_bia',
      value: 'return_to_bia',
      disabled: isReturningToBia.value,
    });
  }

  if (!currentChat.value.muted) {
    items.push({
      icon: 'i-lucide-volume-off',
      label: t('CONTACT_PANEL.MUTE_CONTACT'),
      action: 'mute',
      value: 'mute',
    });
  } else {
    items.push({
      icon: 'i-lucide-volume-1',
      label: t('CONTACT_PANEL.UNMUTE_CONTACT'),
      action: 'unmute',
      value: 'unmute',
    });
  }

  items.push({
    icon: 'i-lucide-share',
    label: t('CONTACT_PANEL.SEND_TRANSCRIPT'),
    action: 'send_transcript',
    value: 'send_transcript',
  });

  return items;
});

const expectedLastMessageId = () => {
  return (
    currentChat.value?.last_non_activity_message?.id ||
    [...(currentChat.value?.messages || [])]
      .reverse()
      .find(message => message.message_type !== MESSAGE_TYPE.ACTIVITY)?.id ||
    null
  );
};

const sendToHumanQueue = async () => {
  if (isAutomationTransitioning.value) return;

  isSendingToQueue.value = true;
  try {
    const confirmed = await confirmSendToQueueDialog.value.showConfirmation();
    if (!confirmed) return;

    await store.dispatch('sendToHumanQueue', {
      conversationId: currentChat.value.id,
      idempotencyKey: `queue-${Date.now()}-${getUuid()}`,
      expectedLastMessageId: expectedLastMessageId(),
      expectedSessionGeneration: Number(
        currentChat.value?.custom_attributes?.bia_session_generation || 0
      ),
    });
    useAlert(t('CONVERSATION.SEND_TO_HUMAN_QUEUE.SUCCESS'));
  } catch (error) {
    const message =
      error.response?.status === 409
        ? t('CONVERSATION.SEND_TO_HUMAN_QUEUE.CONFLICT')
        : t('CONVERSATION.SEND_TO_HUMAN_QUEUE.ERROR');
    useAlert(message);
  } finally {
    isSendingToQueue.value = false;
  }
};

const returnToBia = async () => {
  if (isAutomationTransitioning.value) return;

  isReturningToBia.value = true;
  try {
    const confirmed = await confirmReturnToBiaDialog.value.showConfirmation();
    if (!confirmed) return;

    await store.dispatch('returnToBia', {
      conversationId: currentChat.value.id,
      idempotencyKey: `bia-${Date.now()}-${getUuid()}`,
      expectedLastMessageId: expectedLastMessageId(),
      expectedAssigneeId: currentChat.value?.meta?.assignee?.id || null,
      expectedSessionGeneration: Number(
        currentChat.value?.custom_attributes?.bia_session_generation || 0
      ),
    });
    useAlert(t('CONVERSATION.RETURN_TO_BIA.SUCCESS'));
  } catch (error) {
    const message =
      error.response?.status === 409
        ? t('CONVERSATION.RETURN_TO_BIA.CONFLICT')
        : t('CONVERSATION.RETURN_TO_BIA.ERROR');
    useAlert(message);
  } finally {
    isReturningToBia.value = false;
  }
};

const handleActionClick = async ({ action }) => {
  toggleDropdown(false);

  if (action === 'send_to_human_queue') {
    await sendToHumanQueue();
  } else if (action === 'return_to_bia') {
    await returnToBia();
  } else if (action === 'mute') {
    store.dispatch('muteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
  } else if (action === 'unmute') {
    store.dispatch('unmuteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  }
};

// These functions are needed for the event listeners
const mute = () => {
  store.dispatch('muteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
};

const unmute = () => {
  store.dispatch('unmuteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
};

emitter.on(CMD_MUTE_CONVERSATION, mute);
emitter.on(CMD_UNMUTE_CONVERSATION, unmute);
emitter.on(CMD_SEND_TRANSCRIPT, toggleEmailModal);

onUnmounted(() => {
  emitter.off(CMD_MUTE_CONVERSATION, mute);
  emitter.off(CMD_UNMUTE_CONVERSATION, unmute);
  emitter.off(CMD_SEND_TRANSCRIPT, toggleEmailModal);
});
</script>

<template>
  <div class="relative flex items-center gap-2 actions--container">
    <ResolveAction
      :conversation-id="currentChat.id"
      :status="currentChat.status"
    />
    <div
      v-on-clickaway="() => toggleDropdown(false)"
      class="relative flex items-center group"
    >
      <ButtonV4
        v-tooltip="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-more-vertical"
        class="rounded-md group-hover:bg-n-alpha-2"
        :disabled="isAutomationTransitioning"
        :is-loading="isAutomationTransitioning"
        @click="toggleDropdown()"
      />
      <DropdownMenu
        v-if="showActionsDropdown"
        :menu-items="actionMenuItems"
        class="mt-1 ltr:right-0 rtl:left-0 top-full"
        @action="handleActionClick"
      />
    </div>
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailModal"
    />
    <woot-confirm-modal
      ref="confirmSendToQueueDialog"
      :title="$t('CONVERSATION.SEND_TO_HUMAN_QUEUE.CONFIRM_TITLE')"
      :description="$t('CONVERSATION.SEND_TO_HUMAN_QUEUE.CONFIRM_DESCRIPTION')"
      :confirm-label="$t('CONVERSATION.SEND_TO_HUMAN_QUEUE.CONFIRM_ACTION')"
      :cancel-label="$t('CONVERSATION.SEND_TO_HUMAN_QUEUE.CANCEL')"
    />
    <woot-confirm-modal
      ref="confirmReturnToBiaDialog"
      :title="$t('CONVERSATION.RETURN_TO_BIA.CONFIRM_TITLE')"
      :description="$t('CONVERSATION.RETURN_TO_BIA.CONFIRM_DESCRIPTION')"
      :confirm-label="$t('CONVERSATION.RETURN_TO_BIA.CONFIRM_ACTION')"
      :cancel-label="$t('CONVERSATION.RETURN_TO_BIA.CANCEL')"
    />
  </div>
</template>
