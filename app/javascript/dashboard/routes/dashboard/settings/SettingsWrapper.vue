<script setup>
import { useRoute } from 'vue-router';

defineProps({
  keepAlive: {
    type: Boolean,
    default: true,
  },
});

const route = useRoute();
</script>

<template>
  <div
    class="flex flex-col w-full h-full m-0 pb-8 pt-4 px-6 overflow-auto bg-n-surface-1"
    style="background: radial-gradient(ellipse at top right, rgba(29, 161, 255, 0.08) 0%, transparent 48%);"
  >
    <div class="flex items-start w-full max-w-5xl mx-auto rounded-2xl border border-n-weak/70 bg-n-surface-2/45 p-4 shadow-[0_10px_24px_rgba(2,8,20,0.2)]">
      <router-view v-slot="{ Component }">
        <keep-alive v-if="keepAlive">
          <component :is="Component" :key="route.fullPath" />
        </keep-alive>
        <component :is="Component" v-else :key="route.fullPath" />
      </router-view>
    </div>
  </div>
</template>
