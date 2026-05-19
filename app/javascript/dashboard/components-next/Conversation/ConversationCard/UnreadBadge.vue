<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  count: { type: Number, required: true },
  alignBottom: { type: Boolean, default: false },
});

const { t } = useI18n();

const displayCount = computed(() =>
  props.count > 9 ? t('CHAT_LIST.UNREAD_COUNT_OVERFLOW') : props.count
);
</script>

<template>
  <span
    v-if="count > 0"
    class="bg-n-blue-9 rounded-full h-4 min-w-4 max-w-6 px-1.5 w-fit font-semibold text-xxs leading-3 text-white inline-grid place-items-center flex-shrink-0 shadow-[0_0_0_2px_rgba(17,27,46,0.85)]"
    :class="{
      'mb-0.5': alignBottom,
    }"
  >
    {{ displayCount }}
  </span>
  <span v-else />
</template>
