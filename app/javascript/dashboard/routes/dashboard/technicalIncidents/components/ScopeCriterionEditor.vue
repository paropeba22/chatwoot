<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CatalogMultiSelect from './CatalogMultiSelect.vue';
import { catalogLabel } from '../helpers/formCatalog';

const props = defineProps({
  criterion: { type: Object, required: true },
  fields: { type: Array, required: true },
  operators: { type: Array, required: true },
  usedTypes: { type: Array, default: () => [] },
  inputId: { type: String, required: true },
});
const emit = defineEmits(['update:criterion', 'remove']);
const { t } = useI18n();
const field = computed(() =>
  props.fields.find(option => option.value === props.criterion.criterion_type)
);
const allowedOperators = computed(() =>
  props.operators.filter(option =>
    field.value?.allowed_operators.includes(option.value)
  )
);
const update = attributes =>
  emit('update:criterion', { ...props.criterion, ...attributes });
const scalarText = computed({
  get: () =>
    Array.isArray(props.criterion.values)
      ? props.criterion.values.join('\n')
      : '',
  set: value =>
    update({
      values: value
        .split(/[\n,]/)
        .map(item => item.trim())
        .filter(Boolean),
    }),
});

const valueFieldLabel = name => {
  const labels = {
    city: t('TECHNICAL_INCIDENTS.CATALOG.VALUE_FIELDS.CITY'),
    neighborhood: t('TECHNICAL_INCIDENTS.CATALOG.VALUE_FIELDS.NEIGHBORHOOD'),
    street: t('TECHNICAL_INCIDENTS.CATALOG.VALUE_FIELDS.STREET'),
  };
  return labels[name] || name;
};
const changeField = criterionType => {
  const nextField = props.fields.find(option => option.value === criterionType);
  update({
    criterion_type: criterionType,
    operator: nextField?.allowed_operators?.[0] || 'in',
    values: [],
  });
};
const updateLocation = (index, name, value) => {
  const values = props.criterion.values.map((entry, currentIndex) =>
    currentIndex === index ? { ...entry, [name]: value } : entry
  );
  update({ values });
};
const addLocation = () => {
  const entry = Object.fromEntries(
    (field.value?.value_fields || []).map(name => [name, ''])
  );
  update({ values: [...props.criterion.values, entry] });
};
const removeLocation = index =>
  update({
    values: props.criterion.values.filter(
      (_, currentIndex) => currentIndex !== index
    ),
  });
</script>

<template>
  <div class="grid gap-3 rounded-lg border border-n-weak bg-n-alpha-1 p-3">
    <div class="grid gap-3 md:grid-cols-2">
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('TECHNICAL_INCIDENTS.FORM.SCOPE_FIELD') }}
        </span>
        <select
          :id="`${inputId}-field`"
          :value="criterion.criterion_type"
          class="rounded-lg border border-n-strong bg-n-solid-1 px-3 py-2 text-n-slate-12"
          @change="changeField($event.target.value)"
        >
          <option v-if="!field" :value="criterion.criterion_type" disabled>
            {{
              t('TECHNICAL_INCIDENTS.FORM.UNKNOWN_LEGACY_VALUE', {
                value: criterion.criterion_type,
              })
            }}
          </option>
          <option
            v-for="option in fields"
            :key="option.value"
            :value="option.value"
            :disabled="
              usedTypes.includes(option.value) &&
              option.value !== criterion.criterion_type
            "
          >
            {{ catalogLabel(option, t) }}
          </option>
        </select>
      </label>
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('TECHNICAL_INCIDENTS.FORM.SCOPE_OPERATOR') }}
        </span>
        <select
          :id="`${inputId}-operator`"
          :value="criterion.operator"
          class="rounded-lg border border-n-strong bg-n-solid-1 px-3 py-2 text-n-slate-12"
          @change="update({ operator: $event.target.value })"
        >
          <option
            v-for="option in allowedOperators"
            :key="option.value"
            :value="option.value"
          >
            {{ catalogLabel(option, t) }}
          </option>
        </select>
      </label>
    </div>

    <p v-if="field?.value_type === 'none'" class="text-sm text-n-slate-11">
      {{ t('TECHNICAL_INCIDENTS.FORM.GENERAL_SCOPE_HELP') }}
    </p>

    <CatalogMultiSelect
      v-else-if="field?.value_type === 'catalog_multi_select'"
      :model-value="criterion.values"
      :options="field.available_values"
      :label="t('TECHNICAL_INCIDENTS.FORM.SCOPE_VALUES')"
      :input-id="`${inputId}-values`"
      @update:model-value="update({ values: $event })"
    />

    <label v-else-if="field?.value_type === 'string_list'" class="grid gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('TECHNICAL_INCIDENTS.FORM.SCOPE_VALUES') }}
      </span>
      <textarea
        v-model="scalarText"
        rows="3"
        class="rounded-lg border border-n-strong bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
        :placeholder="t('TECHNICAL_INCIDENTS.FORM.SCOPE_VALUES_PLACEHOLDER')"
      />
      <span class="text-xs text-n-slate-10">
        {{ t('TECHNICAL_INCIDENTS.FORM.SCOPE_VALUES_HELP') }}
      </span>
    </label>

    <div v-else-if="field?.value_type === 'location_pairs'" class="grid gap-2">
      <p class="text-xs font-medium text-n-slate-11">
        {{ t('TECHNICAL_INCIDENTS.FORM.SCOPE_VALUES') }}
      </p>
      <div
        v-for="(entry, entryIndex) in criterion.values"
        :key="entryIndex"
        class="grid gap-2 md:grid-cols-[1fr_1fr_auto]"
      >
        <label
          v-for="name in field.value_fields"
          :key="name"
          class="grid gap-1"
        >
          <span class="sr-only">{{ valueFieldLabel(name) }}</span>
          <input
            :value="entry[name]"
            class="rounded-lg border border-n-strong bg-n-solid-1 px-3 py-2 text-n-slate-12"
            :placeholder="valueFieldLabel(name)"
            @input="updateLocation(entryIndex, name, $event.target.value)"
          />
        </label>
        <button
          type="button"
          class="text-sm text-n-ruby-11"
          @click="removeLocation(entryIndex)"
        >
          {{ t('TECHNICAL_INCIDENTS.REMOVE') }}
        </button>
      </div>
      <button
        type="button"
        class="justify-self-start text-sm font-medium text-n-brand"
        @click="addLocation"
      >
        {{ t('TECHNICAL_INCIDENTS.FORM.ADD_SCOPE_VALUE') }}
      </button>
    </div>

    <button
      type="button"
      class="justify-self-end text-sm text-n-ruby-11"
      @click="emit('remove')"
    >
      {{ t('TECHNICAL_INCIDENTS.FORM.REMOVE_CRITERION') }}
    </button>
  </div>
</template>
