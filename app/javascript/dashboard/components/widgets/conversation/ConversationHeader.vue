<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useElementSize } from '@vueuse/core';
import BackButton from '../BackButton.vue';
import InboxName from '../InboxName.vue';
import MoreActions from './MoreActions.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import wootConstants from 'dashboard/constants/globals';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { buildConversationFilterQuery } from 'dashboard/helper/conversationFilterQueryHelper';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import { useInbox } from 'dashboard/composables/useInbox';
import { useI18n } from 'vue-i18n';
import {
  getConversationSignal,
  getConversationPresentationSignal,
} from 'dashboard/helper/conversationSignal';
import { useOperationsBranding } from 'shared/composables/useOperationsBranding';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
  showBackButton: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const operationsBranding = useOperationsBranding();
const store = useStore();
const route = useRoute();
const conversationHeader = ref(null);
const { width } = useElementSize(conversationHeader);
const { isAWebWidgetInbox } = useInbox();

const currentChat = computed(() => store.getters.getSelectedChat);
const accountId = computed(() => store.getters.getCurrentAccountId);

const chatMetadata = computed(() => props.chat.meta);

const backButtonUrl = computed(() => {
  const {
    params: { inbox_id: inboxId, label, teamId, id: customViewId },
    name,
  } = route;

  const conversationTypeMap = {
    conversation_through_mentions: 'mention',
    conversation_through_participating: 'participating',
    conversation_through_unattended: 'unattended',
  };
  const listUrl = conversationListPageURL({
    accountId: accountId.value,
    inboxId,
    label,
    teamId,
    conversationType: conversationTypeMap[name],
    customViewId,
  });

  const query = buildConversationFilterQuery({
    view: route.query.view,
    status: route.query.status,
  });

  return query ? `${listUrl}?${new URLSearchParams(query)}` : listUrl;
});

const isHMACVerified = computed(() => {
  if (!isAWebWidgetInbox.value) {
    return true;
  }
  return chatMetadata.value.hmac_verified;
});

const currentContact = computed(() =>
  store.getters['contacts/getContact'](props.chat.meta.sender.id)
);

const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const snoozedDisplayText = computed(() => {
  const { snoozed_until: snoozedUntil } = currentChat.value;
  if (snoozedUntil) {
    return `${t('CONVERSATION.HEADER.SNOOZED_UNTIL')} ${snoozedReopenTime(snoozedUntil)}`;
  }
  return t('CONVERSATION.HEADER.SNOOZED_UNTIL_NEXT_REPLY');
});

const inbox = computed(() => {
  const { inbox_id: inboxId } = props.chat;
  return store.getters['inboxes/getInbox'](inboxId);
});

const hasMultipleInboxes = computed(
  () => store.getters['inboxes/getInboxes'].length > 1
);
const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);
const signalState = computed(() => getConversationSignal(props.chat));
const presentationSignal = computed(() =>
  getConversationPresentationSignal(props.chat)
);
const signalLabel = computed(() =>
  ({
    human: t('CONVERSATION.OPERATIONS.SIGNAL.HUMAN'),
    bia: t('CONVERSATION.OPERATIONS.SIGNAL.BIA', {
      aiName: operationsBranding.value.aiDisplayName,
    }),
    queue: t('CONVERSATION.OPERATIONS.SIGNAL.QUEUE'),
    neutral: t('CONVERSATION.OPERATIONS.SIGNAL.NEUTRAL'),
    resolved: t('CONVERSATION.OPERATIONS.SIGNAL.RESOLVED'),
  })[presentationSignal.value]
);
const assigneeName = computed(() => props.chat?.meta?.assignee?.name);
const contactPhone = computed(() => currentContact.value?.phone_number);

const signalPillClass = computed(
  () =>
    ({
      human: 'bg-n-blue-3/70 text-n-blue-11 border-n-blue-8/30',
      bia: 'bg-n-teal-3/70 text-n-teal-11 border-n-teal-8/30',
      queue: 'bg-n-amber-3/70 text-n-amber-11 border-n-amber-8/30',
      neutral: 'bg-n-slate-3/70 text-n-slate-11 border-n-weak',
    })[signalState.value]
);

const signalIcon = computed(
  () =>
    ({
      human: 'i-lucide-headset',
      bia: 'i-lucide-bot',
      queue: 'i-lucide-clock-3',
      neutral: 'i-lucide-message-circle',
    })[signalState.value]
);
</script>

<template>
  <div
    ref="conversationHeader"
    class="gt-conversation-header relative z-30 overflow-visible flex flex-col gap-3 items-center justify-between flex-1 w-full min-w-0 lg:flex-row px-4 py-3 min-h-[4.5rem] border-b border-n-weak/70 bg-n-surface-2/85"
    :data-signal="signalState"
  >
    <div
      class="flex items-center justify-start w-full lg:w-auto max-w-full min-w-0 lg:flex-1"
    >
      <BackButton
        v-if="showBackButton"
        :back-url="backButtonUrl"
        class="ltr:mr-2 rtl:ml-2"
      />
      <Avatar
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="36"
        :status="currentContact.availability_status"
        hide-offline-status
        rounded-full
      />
      <div
        class="flex flex-col items-start min-w-0 ml-3 overflow-hidden rtl:ml-0 rtl:mr-3"
      >
        <div class="flex flex-row items-center max-w-full gap-1 p-0 m-0">
          <span
            class="text-base font-semibold truncate leading-tight text-n-slate-12 tracking-[-0.01em]"
          >
            {{ currentContact.name }}
          </span>
          <fluent-icon
            v-if="!isHMACVerified"
            v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
            size="14"
            class="text-n-amber-10 my-0 mx-0 min-w-[14px] flex-shrink-0"
            icon="warning"
          />
        </div>

        <div
          class="flex items-center gap-2 mt-1 overflow-hidden text-[11px] conversation--header--actions text-ellipsis whitespace-nowrap text-n-slate-10"
        >
          <InboxName v-if="hasMultipleInboxes" :inbox="inbox" class="!mx-0" />
          <span aria-hidden="true" class="size-0.5 rounded-full bg-n-slate-8" />
          <span class="truncate">
            {{
              $t('CONVERSATION.OPERATIONS.REFERENCE', {
                id: currentChat.id,
              })
            }}
          </span>
          <template v-if="contactPhone">
            <span
              aria-hidden="true"
              class="hidden sm:inline-block size-0.5 rounded-full bg-n-slate-8"
            />
            <span class="hidden sm:inline truncate">{{ contactPhone }}</span>
          </template>
          <span v-if="isSnoozed" class="font-medium text-n-amber-10">
            {{ snoozedDisplayText }}
          </span>
        </div>
      </div>
    </div>
    <div
      class="flex flex-row items-center justify-between lg:justify-end flex-shrink-0 gap-2 w-full lg:w-auto header-actions-wrap [&_button]:rounded-[10px] [&_button]:transition-colors"
    >
      <div class="flex items-center gap-2 min-w-0">
        <span
          class="inline-flex items-center gap-1.5 px-2 py-1 rounded-lg border text-[11px] font-semibold whitespace-nowrap"
          :class="signalPillClass"
        >
          <span class="size-3.5" :class="signalIcon" />
          {{ signalLabel }}
        </span>
        <span
          v-if="assigneeName"
          class="hidden 2xl:inline text-xs text-n-slate-10 truncate max-w-36"
        >
          {{ assigneeName }}
        </span>
      </div>
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="hidden md:flex"
      />
      <MoreActions :conversation-id="currentChat.id" />
    </div>
  </div>
</template>
