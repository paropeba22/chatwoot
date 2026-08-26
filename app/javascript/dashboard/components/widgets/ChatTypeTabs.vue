<script setup>
import { computed } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  items: {
    type: Array,
    default: () => [],
  },
  activeTab: {
    type: String,
    default: wootConstants.ASSIGNEE_TYPE.ME,
  },
});

const emit = defineEmits(['chatTabChange']);

const activeTabIndex = computed(() => {
  return props.items.findIndex(item => item.key === props.activeTab);
});

const onTabChange = selectedTabIndex => {
  if (selectedTabIndex >= 0 && selectedTabIndex < props.items.length) {
    const selectedItem = props.items[selectedTabIndex];
    if (selectedItem.key !== props.activeTab) {
      emit('chatTabChange', selectedItem.key);
    }
  }
};

const keyboardEvents = {
  'Alt+KeyN': {
    action: () => {
      if (props.activeTab === wootConstants.ASSIGNEE_TYPE.ALL) {
        onTabChange(0);
      } else {
        const nextIndex = (activeTabIndex.value + 1) % props.items.length;
        onTabChange(nextIndex);
      }
    },
  },
};

useKeyboardEvents(keyboardEvents);
</script>

<template>
  <woot-tabs
    :index="activeTabIndex"
    :show-scroll-buttons="false"
    class="chat-type-tabs w-full min-w-0 max-w-full overflow-x-auto px-2 py-1 min-h-12 [&_ul]:m-0 [&_ul]:w-full [&_ul]:min-w-0 [&_ul]:max-w-full [&_ul]:flex-1 [&_ul]:overflow-x-auto [&_ul]:p-1 [&_ul]:rounded-[10px] [&_ul]:border [&_ul]:border-n-weak/80 [&_ul]:bg-n-solid-2/55 [&_ul]:md:grid [&_ul]:md:grid-cols-4 [&_ul]:md:gap-1 [&_ul]:md:overflow-visible [&_li]:mx-0.5 [&_li]:min-w-[8.5rem] [&_li]:shrink-0 [&_li]:md:mx-0 [&_li]:md:min-w-0 [&_li]:md:shrink [&_a]:rounded-md [&_a]:transition-[background-color,color,box-shadow] [&_a]:duration-150 [&_a]:ease-out [&_a:hover]:bg-n-alpha-2/70 [&_a]:px-2 [&_a]:h-8 [&_a]:justify-center [&_a]:gap-1.5 [&_a]:text-xs [&_a]:font-semibold [&_.is-active>a]:bg-n-blue-9/14 [&_.is-active>a]:shadow-[inset_0_-2px_0_rgb(var(--gt-signal-human)),inset_0_0_0_1px_rgba(29,161,255,0.24)] [&_.is-active>a]:text-n-blue-11"
    @change="onTabChange"
  >
    <woot-tabs-item
      v-for="(item, index) in items"
      :key="item.key"
      class="text-sm [&_a]:font-medium"
      :index="index"
      :name="item.name"
      :count="item.count"
      is-compact
    />
  </woot-tabs>
</template>
