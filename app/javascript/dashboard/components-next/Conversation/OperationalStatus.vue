<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useOperationsBranding } from 'shared/composables/useOperationsBranding';

const props = defineProps({
  state: {
    type: String,
    default: 'neutral',
  },
  compact: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const operationsBranding = useOperationsBranding();

const STATE_CONFIG = {
  human: {
    icon: 'i-lucide-headset',
    tone: 'gt-operational-status--human',
  },
  bia: {
    icon: 'i-lucide-bot',
    tone: 'gt-operational-status--bia',
  },
  queue: {
    icon: 'i-lucide-clock-3',
    tone: 'gt-operational-status--queue',
  },
  resolved: {
    icon: 'i-lucide-circle-check-big',
    tone: 'gt-operational-status--resolved',
  },
  neutral: {
    icon: 'i-lucide-circle-dot-dashed',
    tone: 'gt-operational-status--neutral',
  },
};

const normalizedState = computed(() =>
  Object.prototype.hasOwnProperty.call(STATE_CONFIG, props.state)
    ? props.state
    : 'neutral'
);
const statusConfig = computed(() => STATE_CONFIG[normalizedState.value]);
const label = computed(() => {
  if (normalizedState.value === 'human') {
    return t('CONVERSATION.OPERATIONS.SIGNAL.HUMAN');
  }
  if (normalizedState.value === 'bia') {
    return t('CONVERSATION.OPERATIONS.SIGNAL.BIA', {
      aiName: operationsBranding.value.aiDisplayName,
    });
  }
  if (normalizedState.value === 'queue') {
    return t('CONVERSATION.OPERATIONS.SIGNAL.QUEUE');
  }
  if (normalizedState.value === 'resolved') {
    return t('CONVERSATION.OPERATIONS.SIGNAL.RESOLVED');
  }
  return t('CONVERSATION.OPERATIONS.SIGNAL.NEUTRAL');
});
</script>

<template>
  <span
    class="gt-operational-status"
    :class="[
      statusConfig.tone,
      compact
        ? 'gt-operational-status--compact'
        : 'gt-operational-status--default',
    ]"
    :data-state="normalizedState"
  >
    <span :class="[statusConfig.icon, compact ? 'size-3' : 'size-3.5']" />
    <span class="truncate">{{ label }}</span>
  </span>
</template>
