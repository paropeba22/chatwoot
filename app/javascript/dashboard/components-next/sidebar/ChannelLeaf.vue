<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import {
  getInboxDisplayIcon,
  getInboxDisplayName,
  isGrupoTelecomInbox,
} from 'dashboard/helper/inboxPresentationHelper';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  // eslint-disable-next-line vue/no-unused-properties
  active: {
    type: Boolean,
    default: false,
  },
  inbox: {
    type: Object,
    required: true,
  },
});

const reauthorizationRequired = computed(() => {
  return props.inbox.reauthorization_required;
});

const displayName = computed(() => getInboxDisplayName(props.inbox));
const customIcon = computed(() => getInboxDisplayIcon(props.inbox));
const isGrupoTelecomChannel = computed(() => isGrupoTelecomInbox(props.inbox));
</script>

<template>
  <span
    v-if="isGrupoTelecomChannel"
    class="grid size-5 place-content-center rounded-lg bg-n-teal-4/40 text-n-teal-11 ring-1 ring-n-teal-7/35"
  >
    <Icon :icon="customIcon" class="size-3.5" />
  </span>
  <span v-else class="size-4 grid place-content-center rounded-full">
    <ChannelIcon :inbox="inbox" class="size-4" />
  </span>
  <div
    class="flex-1 truncate min-w-0"
    :class="isGrupoTelecomChannel ? 'font-medium text-n-slate-12' : ''"
  >
    {{ displayName || label }}
  </div>
  <div
    v-if="reauthorizationRequired"
    v-tooltip.top-end="$t('SIDEBAR.REAUTHORIZE')"
    class="grid place-content-center size-5 bg-n-ruby-5/60 rounded-full"
  >
    <Icon icon="i-woot-alert" class="size-3 text-n-ruby-9" />
  </div>
</template>
