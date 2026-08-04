<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { catalogLabel } from '../helpers/formCatalog';

const props = defineProps({
  modelValue: { type: Array, required: true },
  options: { type: Array, required: true },
  label: { type: String, required: true },
  inputId: { type: String, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const query = ref('');
const visibleOptions = computed(() => {
  const normalizedQuery = query.value.trim().toLocaleLowerCase();
  if (!normalizedQuery) return props.options;
  return props.options.filter(option =>
    catalogLabel(option, t).toLocaleLowerCase().includes(normalizedQuery)
  );
});
const selectedOptions = computed(() =>
  props.options.filter(option => props.modelValue.includes(option.value))
);
const unknownValues = computed(() => {
  const known = new Set(props.options.map(option => option.value));
  return props.modelValue.filter(value => !known.has(value));
});
const toggle = option => {
  const values = new Set(props.modelValue);
  if (values.has(option.value)) values.delete(option.value);
  else values.add(option.value);
  emit('update:modelValue', [...values]);
};
</script>

<template>
  <fieldset class="grid min-w-0 gap-2" :disabled="disabled">
    <legend class="text-sm font-medium text-n-slate-12">{{ label }}</legend>
    <input
      v-if="options.length > 7"
      :id="`${inputId}-search`"
      v-model="query"
      type="search"
      class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
      :placeholder="t('TECHNICAL_INCIDENTS.FORM.SEARCH_OPTIONS')"
      :aria-label="t('TECHNICAL_INCIDENTS.FORM.SEARCH_OPTIONS')"
    />
    <div
      class="max-h-40 overflow-auto rounded-lg border border-n-strong bg-n-alpha-1 p-2"
    >
      <label
        v-for="option in visibleOptions"
        :key="option.value"
        class="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm text-n-slate-12 hover:bg-n-alpha-2"
      >
        <input
          :id="`${inputId}-${option.value}`"
          type="checkbox"
          :checked="modelValue.includes(option.value)"
          @change="toggle(option)"
        />
        <span>{{ catalogLabel(option, t) }}</span>
      </label>
      <p v-if="!visibleOptions.length" class="p-2 text-sm text-n-slate-10">
        {{ t('TECHNICAL_INCIDENTS.FORM.NO_SEARCH_RESULTS') }}
      </p>
    </div>
    <div
      v-if="selectedOptions.length || unknownValues.length"
      class="flex flex-wrap gap-1"
      aria-live="polite"
    >
      <span
        v-for="option in selectedOptions"
        :key="option.value"
        class="rounded-full bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-12"
      >
        {{ catalogLabel(option, t) }}
      </span>
      <span
        v-for="value in unknownValues"
        :key="value"
        class="rounded-full bg-n-amber-3 px-2 py-1 text-xs text-n-amber-11"
      >
        {{ t('TECHNICAL_INCIDENTS.FORM.UNKNOWN_LEGACY_VALUE', { value }) }}
      </span>
    </div>
    <p v-else class="text-xs text-n-slate-10">
      {{ t('TECHNICAL_INCIDENTS.FORM.NONE_SELECTED') }}
    </p>
  </fieldset>
</template>
