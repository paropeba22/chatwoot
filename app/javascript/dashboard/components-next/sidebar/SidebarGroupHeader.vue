<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store.js';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  to: { type: [Object, String], default: '' },
  label: { type: String, default: '' },
  icon: { type: [String, Object], default: '' },
  expandable: { type: Boolean, default: false },
  isExpanded: { type: Boolean, default: false },
  isActive: { type: Boolean, default: false },
  hasActiveChild: { type: Boolean, default: false },
  getterKeys: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['toggle']);

const showBadge = useMapGetter(props.getterKeys.badge);
const dynamicCount = useMapGetter(props.getterKeys.count);
const count = computed(() =>
  dynamicCount.value > 99 ? '99+' : dynamicCount.value
);
</script>

<template>
  <component
    :is="to ? 'router-link' : 'div'"
    class="neo-focus-ring flex items-center gap-2 px-2 py-1 rounded-xl h-8 min-w-0 transition-all duration-150"
    role="button"
    draggable="false"
    :to="to"
    :title="label"
    :class="{
      'text-n-slate-12 bg-n-alpha-2/90 outline outline-1 outline-n-blue-8/45 font-medium':
        isActive && !hasActiveChild,
      'text-n-slate-12 font-medium bg-n-alpha-1/50': hasActiveChild,
      'text-n-slate-11 hover:bg-n-alpha-2/70 hover:text-n-slate-12':
        !isActive && !hasActiveChild,
    }"
    @click.stop="emit('toggle')"
  >
    <div v-if="icon" class="relative flex items-center gap-2">
      <Icon v-if="icon" :icon="icon" class="size-4" />
      <span
        v-if="showBadge"
        class="size-2 -top-px ltr:-right-px rtl:-left-px bg-n-brand absolute rounded-full border border-n-solid-2"
      />
    </div>
    <div class="flex items-center gap-1.5 flex-grow min-w-0 flex-1">
      <span
        class="truncate"
        :class="{
          'text-body-main': !isActive,
          'font-medium text-sm': isActive || hasActiveChild,
        }"
      >
        {{ label }}
      </span>
      <span
        v-if="dynamicCount && !expandable"
        class="rounded-lg capitalize text-xs leading-5 font-medium text-center outline outline-1 px-1.5 flex-shrink-0"
        :class="{
          'text-n-slate-12 outline-n-blue-8/45 bg-n-slate-3/60': isActive,
          'text-n-slate-11 outline-n-strong bg-transparent': !isActive,
        }"
      >
        {{ count }}
      </span>
    </div>
    <span
      v-if="expandable"
      v-show="isExpanded"
      class="i-lucide-chevron-up size-3"
      @click.stop="emit('toggle')"
    />
  </component>
</template>
