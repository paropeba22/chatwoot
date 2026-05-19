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
    class="chat-type-tabs w-full px-3 py-0.5 h-11 [&_ul]:m-0 [&_ul]:p-1 [&_ul]:rounded-[var(--gt-radius-pill)] [&_ul]:outline [&_ul]:outline-1 [&_ul]:outline-n-weak/80 [&_ul]:bg-n-solid-2/75 [&_a]:rounded-[var(--gt-radius-pill)] [&_a]:transition-all [&_a]:duration-150 [&_a]:ease-out [&_a:hover]:bg-n-alpha-2/70 [&_a]:px-2.5 [&_a]:h-8 [&_.is-active>a]:bg-n-blue-9/20 [&_.is-active>a]:outline [&_.is-active>a]:outline-1 [&_.is-active>a]:outline-n-blue-8/50 [&_.is-active>a]:text-n-slate-12"
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
