<script>
import FeaturePlaceholder from './FeaturePlaceholder.vue';
export default {
  components: { FeaturePlaceholder },
  props: {
    message: {
      type: String,
      required: true,
    },
  },
};
</script>

<template>
  <div
    class="gt-conversation-empty flex flex-col items-center justify-center h-full px-6"
  >
    <div
      class="grid place-items-center size-14 mb-4 rounded-[var(--gt-radius-md)] border border-n-blue-8/25 bg-n-blue-9/10"
    >
      <span class="i-lucide-radio-tower size-6 text-n-blue-11" />
    </div>
    <span
      class="max-w-sm text-sm text-n-slate-11 font-medium text-center leading-6"
    >
      {{ message }}
    </span>
    <!-- Cmd bar, keyboard shortcuts placeholder -->
    <FeaturePlaceholder />
  </div>
</template>
