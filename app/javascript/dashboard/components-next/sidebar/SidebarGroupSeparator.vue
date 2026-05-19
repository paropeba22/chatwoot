<script setup>
import Icon from 'next/icon/Icon.vue';

defineProps({
  label: {
    type: String,
    default: '',
  },
  icon: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div
    class="flex items-center gap-2 px-2 py-1.5 rounded-xl h-8 text-n-slate-10/90 select-none pointer-events-none bg-n-alpha-1/35"
  >
    <Icon v-if="icon" :icon="icon" class="size-4" />
    <span class="text-sm font-medium leading-5 flex-grow">
      {{ label }}
    </span>
  </div>
</template>
