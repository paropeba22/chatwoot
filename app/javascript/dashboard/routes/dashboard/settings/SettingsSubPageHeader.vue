<script>
export default {
  props: {
    headerTitle: { type: String, default: '' },
    headerContent: { type: String, default: '' },
  },
};
</script>

<template>
  <div class="flex flex-col gap-1.5 w-full items-start mb-4 p-4 rounded-xl border border-n-weak/70 bg-n-surface-2/40">
    <h2 class="text-heading-1 text-n-slate-12 break-words">
      {{ headerTitle }}
    </h2>
    <p
      v-dompurify-html="headerContent"
      class="text-body-main w-full text-n-slate-11"
    />
  </div>
</template>
