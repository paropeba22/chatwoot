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
  <div class="flex flex-col items-center justify-center h-full px-6">
    <div
      class="grid place-items-center size-16 mb-5 rounded-2xl border border-n-blue-8/25 bg-n-blue-9/10 shadow-[0_14px_30px_rgba(2,8,20,0.18)]"
    >
      <span class="i-lucide-headphones size-7 text-n-blue-11" />
    </div>
    <span class="max-w-sm text-sm text-n-slate-11 font-medium text-center">
      {{ message }}
    </span>
    <!-- Cmd bar, keyboard shortcuts placeholder -->
    <FeaturePlaceholder />
  </div>
</template>
