<script setup>
defineProps({
  isLoading: {
    type: Boolean,
    default: false,
  },
  noRecordsFound: {
    type: Boolean,
    default: false,
  },
  loadingMessage: {
    type: String,
    default: '',
  },
  noRecordsMessage: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div class="flex flex-col w-full h-full gap-4 font-inter rounded-2xl">
    <slot name="header" />
    <!-- Added to render any templates that should be rendered before body -->
    <main class="rounded-2xl border border-n-weak/70 bg-n-surface-2/35 p-4 shadow-[0_8px_20px_rgba(2,8,20,0.14)]">
      <slot name="preBody" />
      <slot v-if="isLoading" name="loading">
        <woot-loading-state :message="loadingMessage" />
      </slot>
      <p
        v-else-if="noRecordsFound"
        class="flex-1 py-20 text-n-slate-12 flex items-center justify-center text-base"
      >
        {{ noRecordsMessage }}
      </p>
      <slot v-else name="body" />
      <!-- Do not delete the slot below. It is required to render anything that is not defined in the above slots. -->
      <slot />
    </main>
  </div>
</template>
