<script setup>
import { computed } from 'vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Icon from 'next/icon/Icon.vue';
import {
  getInboxChipLabel,
  getInboxDisplayIcon,
  isGrupoTelecomInbox,
} from 'dashboard/helper/inboxPresentationHelper';

const props = defineProps({
  inbox: {
    type: Object,
    default: () => {},
  },
});

const chipLabel = computed(() => getInboxChipLabel(props.inbox));
const customIcon = computed(() => getInboxDisplayIcon(props.inbox));
const isGrupoTelecomChannel = computed(() => isGrupoTelecomInbox(props.inbox));
</script>

<template>
  <div
    :title="chipLabel"
    class="inline-flex items-center min-w-0 gap-1 rounded-full border px-1.5 py-0.5"
    :class="
      isGrupoTelecomChannel
        ? 'border-n-teal-7/40 bg-n-teal-4/25 text-n-teal-11'
        : 'border-transparent text-n-slate-11'
    "
  >
    <span
      v-if="isGrupoTelecomChannel"
      class="grid size-4 flex-shrink-0 place-content-center rounded-full bg-n-teal-9/15 text-n-teal-11"
    >
      <Icon :icon="customIcon" class="size-3.5" />
    </span>
    <ChannelIcon
      v-else
      :inbox="inbox"
      class="size-4 flex-shrink-0 text-n-slate-11"
    />
    <span class="truncate text-label-small font-medium">
      {{ chipLabel }}
    </span>
  </div>
</template>
