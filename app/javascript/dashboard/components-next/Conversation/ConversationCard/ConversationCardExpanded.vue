<script setup>
import { computed, useTemplateRef } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import CardAvatar from './CardAvatar.vue';
import CardContent from './CardContent.vue';
import CardLabels from './CardLabelsV5.vue';
import CardPriorityIcon from './CardPriorityIcon.vue';
import InboxName from 'dashboard/components-next/Conversation/InboxName.vue';
import Avatar from 'next/avatar/Avatar.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import SLACardLabel from 'dashboard/components-next/Conversation/Sla/SLACardLabel.vue';
import CardStatusIcon from './CardStatusIcon.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import OperationalStatus from 'dashboard/components-next/Conversation/OperationalStatus.vue';
import {
  getConversationPresentationSignal,
  visibleConversationLabels,
} from 'dashboard/helper/conversationSignal';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  isInboxView: { type: Boolean, default: false },
});

const emit = defineEmits([
  'selectConversation',
  'deSelectConversation',
  'click',
  'contextmenu',
]);

const lastMessageInChat = computed(() => getLastMessage(props.chat));
const presentationSignal = computed(() =>
  getConversationPresentationSignal(props.chat)
);
const visibleLabels = computed(() => visibleConversationLabels(props.chat));
const showLabelsSection = computed(() => visibleLabels.value.length > 0);

const voiceCallData = computed(() => ({
  status: props.chat.additional_attributes?.call_status,
  direction: props.chat.additional_attributes?.call_direction,
}));

const unreadCount = computed(() => props.chat.unread_count);

const slaCardLabel = useTemplateRef('slaCardLabel');

const hasSlaPolicyId = computed(
  () => props.chat?.sla_policy_id || slaCardLabel.value?.hasSlaThreshold
);

const selectedModel = computed({
  get: () => props.selected,
  set: value => {
    if (value) {
      emit('selectConversation', value);
    } else {
      emit('deSelectConversation', value);
    }
  },
});
</script>

<template>
  <div
    class="gt-conversation-card conversation relative cursor-pointer group grid gap-3 items-center px-3 h-14 my-1 mx-2 rounded-[var(--gt-radius-md)] border transition-[background-color,border-color,box-shadow] duration-150"
    :data-signal="presentationSignal"
    :class="{
      'active animate-card-select': isActiveChat,
      selected,
      'grid-cols-[minmax(0,2fr)_minmax(0,1fr)]': showLabelsSection,
      'grid-cols-[minmax(0,2fr)_max-content]': !showLabelsSection,
    }"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <!-- LEFT SECTION -->
    <div class="flex items-center gap-2 min-w-0 flex-1">
      <div class="flex items-center justify-center flex-shrink-0" @click.stop>
        <Checkbox v-model="selectedModel" />
      </div>

      <div class="w-px h-3 bg-n-slate-6 flex-shrink-0" />

      <div class="w-4 flex items-center justify-center flex-shrink-0">
        <CardPriorityIcon :priority="chat.priority" show-empty />
      </div>

      <div class="w-4 flex items-center justify-center flex-shrink-0">
        <Avatar
          v-if="showAssignee && assignee.name"
          v-tooltip.top="{
            content: assignee.name,
            delay: { show: 500, hide: 0 },
          }"
          :name="assignee.name"
          :src="assignee.thumbnail"
          :size="14"
          :status="assignee.availability_status"
          hide-offline-status
        />
        <Icon
          v-else
          icon="i-woot-empty-assignee"
          class="size-4 text-n-slate-7"
        />
      </div>

      <div class="w-4 flex items-center justify-center flex-shrink-0">
        <CardStatusIcon :status="chat.status" show-empty />
      </div>

      <div class="w-px h-3 bg-n-slate-6 flex-shrink-0" />

      <div v-if="!isInboxView && showInboxName" class="w-20 flex-shrink-0">
        <InboxName v-if="showInboxName" :inbox="inbox" class="min-w-0" />
      </div>

      <div
        v-if="!isInboxView && showInboxName"
        class="w-px h-3 bg-n-slate-6 flex-shrink-0"
      />

      <CardAvatar
        :contact="currentContact"
        :selected="false"
        :enable-selection="false"
        :hide-thumbnail="false"
      />

      <h4
        class="text-heading-3 my-0 capitalize truncate text-n-slate-12 font-semibold w-40 flex-shrink-0"
      >
        {{ currentContact.name }}
      </h4>

      <OperationalStatus
        :state="presentationSignal"
        compact
        class="hidden lg:inline-flex"
      />

      <CardContent
        :last-message="lastMessageInChat"
        :voice-call-status="voiceCallData.status"
        :voice-call-direction="voiceCallData.direction"
        :unread-count="unreadCount"
        :show-expanded-preview="false"
      />
    </div>

    <!-- RIGHT SECTION -->
    <div class="flex items-center justify-end gap-1.5 flex-shrink-0">
      <div v-if="showLabelsSection" class="min-w-0 w-full">
        <CardLabels
          :labels="visibleLabels"
          disable-toggle
          class="my-0 [&>div]:justify-end justify-end"
        />
      </div>

      <div v-if="hasSlaPolicyId" class="flex-shrink-0">
        <SLACardLabel ref="slaCardLabel" :chat="chat" />
      </div>

      <div class="flex-shrink-0 w-[4.375rem] text-end">
        <TimeAgo
          :conversation-id="chat.id"
          :last-activity-timestamp="chat.timestamp"
          :created-at-timestamp="chat.created_at"
          class="font-440 !text-xs text-n-slate-11"
        />
      </div>
    </div>
  </div>
</template>
