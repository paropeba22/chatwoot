<script setup>
import { computed } from 'vue';
import { messageStamp, messageTimestamp } from 'shared/helpers/timeHelper';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { content, createdAt } = useMessageContext();

const readableTime = computed(() =>
  messageTimestamp(createdAt.value, 'LLL d, h:mm a')
);
const shortTime = computed(() => messageStamp(createdAt.value));
</script>

<template>
  <BaseBubble
    v-tooltip.top="readableTime"
    class="gt-activity-event px-3 py-1.5 !rounded-lg flex min-w-0 items-center gap-2"
    data-bubble-name="activity"
  >
    <span
      class="i-lucide-activity size-3.5 flex-shrink-0 text-n-slate-9"
      aria-hidden="true"
    />
    <span v-dompurify-html="content" :title="content" />
    <time
      class="flex-shrink-0 text-xxs text-n-slate-10 before:mr-2 before:text-n-slate-8 before:content-['·']"
    >
      {{ shortTime }}
    </time>
  </BaseBubble>
</template>
