<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import CatalogMultiSelect from '../components/CatalogMultiSelect.vue';
import ScopeCriterionEditor from '../components/ScopeCriterionEditor.vue';
import {
  catalogLabel,
  createCriterion,
  createScopeGroup,
  emptyMetadata,
  hydrateScopeGroups,
  serializeScopeGroups,
  validateIncidentForm,
} from '../helpers/formCatalog';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const parseError = ref('');
const attemptedSubmit = ref(false);
const componentActive = ref(true);
const metadataRequested = ref(false);
const incidentLoadError = ref(false);
const incidentLoaded = ref(false);
const isEditing = computed(() => Boolean(route.params.incidentId));
const options = computed(
  () =>
    store.getters['technicalIncidents/getTechnicalIncidentOptions'] ||
    emptyMetadata()
);
const uiFlags = computed(
  () => store.getters['technicalIncidents/getTechnicalIncidentUIFlags']
);
const metadataEmpty = computed(() =>
  [
    options.value.incident_types,
    options.value.severities,
    options.value.actions,
    options.value.problem_types,
    options.value.affected_services,
    options.value.scope_fields,
    options.value.scope_operators,
  ].some(catalog => !catalog?.length)
);
const metadataReady = computed(
  () =>
    !uiFlags.value.fetchingOptions &&
    !uiFlags.value.optionsError &&
    !metadataEmpty.value
);

const form = reactive({
  title: '',
  incident_type: 'unplanned_outage',
  severity: 'minor',
  priority: 50,
  problem_types: ['internet_connectivity'],
  affected_services: ['internet'],
  action: 'message_and_handoff',
  starts_at: '',
  expires_at: '',
  review_at: '',
  estimated_resolution_at: '',
  customer_message: '',
  internal_note: '',
  resend_on_next_contact: false,
  lock_version: 0,
  scope_groups_attributes: [createScopeGroup(0)],
});

const unknownVariables = computed(() =>
  [...form.customer_message.matchAll(/\{\{\s*([a-z_]+)\s*\}\}/g)]
    .map(match => match[1])
    .filter(variable => !options.value.template_variables?.includes(variable))
);
const preview = computed(() => {
  const replacements = {
    incident_title: form.title,
    affected_service:
      form.affected_services.length === 1 ? form.affected_services[0] : '',
    estimated_resolution_at: form.estimated_resolution_at,
  };
  return form.customer_message.replace(
    /\{\{\s*([a-z_]+)\s*\}\}/g,
    (_, variable) => replacements[variable] || `{{${variable}}}`
  );
});
const formErrors = computed(() =>
  metadataReady.value ? validateIncidentForm(form, options.value) : []
);
const canSave = computed(
  () => metadataReady.value && !uiFlags.value.saving && !formErrors.value.length
);
const selectedAction = computed(() =>
  options.value.actions?.find(option => option.value === form.action)
);

const hydrate = incident =>
  Object.assign(form, {
    ...incident,
    title: incident.title || '',
    incident_type: incident.incident_type || '',
    severity: incident.severity || '',
    priority: Number.isInteger(incident.priority) ? incident.priority : 50,
    problem_types: Array.isArray(incident.problem_types)
      ? incident.problem_types
      : [],
    affected_services: Array.isArray(incident.affected_services)
      ? incident.affected_services
      : [],
    action: incident.action || '',
    customer_message: incident.customer_message || '',
    internal_note: incident.internal_note || '',
    starts_at: incident.starts_at?.slice(0, 16) || '',
    expires_at: incident.expires_at?.slice(0, 16) || '',
    review_at: incident.review_at?.slice(0, 16) || '',
    estimated_resolution_at:
      incident.estimated_resolution_at?.slice(0, 16) || '',
    scope_groups_attributes: hydrateScopeGroups(incident.scope_groups || []),
  });
const addGroup = () =>
  form.scope_groups_attributes.push(
    createScopeGroup(form.scope_groups_attributes.length)
  );
const addCriterion = group => {
  const usedTypes = group.criteria_attributes
    .filter(criterion => !Reflect.get(criterion, '_destroy'))
    .map(criterion => criterion.criterion_type);
  const nextType =
    options.value.scope_fields.find(field => !usedTypes.includes(field.value))
      ?.value || 'general';
  group.criteria_attributes.push(createCriterion(nextType));
};
const removeGroup = group => {
  if (group.id) {
    Reflect.set(group, '_destroy', true);
    return;
  }
  form.scope_groups_attributes.splice(
    form.scope_groups_attributes.indexOf(group),
    1
  );
};
const removeCriterion = (group, criterion) => {
  if (criterion.id) {
    Reflect.set(criterion, '_destroy', true);
    return;
  }
  group.criteria_attributes.splice(
    group.criteria_attributes.indexOf(criterion),
    1
  );
};
const serialize = () => ({
  ...form,
  scope_groups_attributes: serializeScopeGroups(form.scope_groups_attributes),
});
const validationMessage = code => {
  const messages = {
    TITLE_REQUIRED: t('TECHNICAL_INCIDENTS.FORM.VALIDATION.TITLE_REQUIRED'),
    TYPE_REQUIRED: t('TECHNICAL_INCIDENTS.FORM.VALIDATION.TYPE_REQUIRED'),
    SEVERITY_REQUIRED: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.SEVERITY_REQUIRED'
    ),
    ACTION_REQUIRED: t('TECHNICAL_INCIDENTS.FORM.VALIDATION.ACTION_REQUIRED'),
    PRIORITY_INVALID: t('TECHNICAL_INCIDENTS.FORM.VALIDATION.PRIORITY_INVALID'),
    PROBLEM_TYPES_REQUIRED: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.PROBLEM_TYPES_REQUIRED'
    ),
    SERVICES_REQUIRED: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.SERVICES_REQUIRED'
    ),
    MESSAGE_REQUIRED: t('TECHNICAL_INCIDENTS.FORM.VALIDATION.MESSAGE_REQUIRED'),
    INVALID_EXPIRATION: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.INVALID_EXPIRATION'
    ),
    INVALID_DATE: t('TECHNICAL_INCIDENTS.FORM.VALIDATION.INVALID_DATE'),
    INVALID_REVIEW: t('TECHNICAL_INCIDENTS.FORM.VALIDATION.INVALID_REVIEW'),
    SCOPE_GROUP_REQUIRED: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.SCOPE_GROUP_REQUIRED'
    ),
    SCOPE_CRITERION_REQUIRED: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.SCOPE_CRITERION_REQUIRED'
    ),
    DUPLICATE_SCOPE_FIELD: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.DUPLICATE_SCOPE_FIELD'
    ),
    SCOPE_FIELD_REQUIRED: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.SCOPE_FIELD_REQUIRED'
    ),
    SCOPE_OPERATOR_INVALID: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.SCOPE_OPERATOR_INVALID'
    ),
    SCOPE_VALUE_REQUIRED: t(
      'TECHNICAL_INCIDENTS.FORM.VALIDATION.SCOPE_VALUE_REQUIRED'
    ),
  };
  return messages[code] || t('TECHNICAL_INCIDENTS.FORM.METADATA_REQUIRED');
};
const actionDescription = action => {
  const descriptions = {
    message_and_handoff: t(
      'TECHNICAL_INCIDENTS.CATALOG.ACTION_DESCRIPTIONS.MESSAGE_AND_HANDOFF'
    ),
    message_only: t(
      'TECHNICAL_INCIDENTS.CATALOG.ACTION_DESCRIPTIONS.MESSAGE_ONLY'
    ),
    handoff_only: t(
      'TECHNICAL_INCIDENTS.CATALOG.ACTION_DESCRIPTIONS.HANDOFF_ONLY'
    ),
  };
  return descriptions[action.value];
};
const dateFieldLabel = fieldName => {
  const labels = {
    starts_at: t('TECHNICAL_INCIDENTS.FORM.STARTS_AT'),
    expires_at: t('TECHNICAL_INCIDENTS.FORM.EXPIRES_AT'),
    review_at: t('TECHNICAL_INCIDENTS.FORM.REVIEW_AT'),
    estimated_resolution_at: t(
      'TECHNICAL_INCIDENTS.FORM.ESTIMATED_RESOLUTION_AT'
    ),
  };
  return labels[fieldName];
};
const save = async () => {
  attemptedSubmit.value = true;
  parseError.value = '';
  if (unknownVariables.value.length) {
    parseError.value = t('TECHNICAL_INCIDENTS.FORM.UNKNOWN_VARIABLE');
    return;
  }
  if (!canSave.value) {
    parseError.value = formErrors.value.length
      ? validationMessage(formErrors.value[0])
      : t('TECHNICAL_INCIDENTS.FORM.METADATA_REQUIRED');
    return;
  }
  try {
    const payload = serialize();
    const incident = isEditing.value
      ? await store.dispatch('technicalIncidents/update', {
          id: route.params.incidentId,
          payload,
        })
      : await store.dispatch('technicalIncidents/create', payload);
    router.push({
      name: 'technical_incidents_show',
      params: { incidentId: incident.id },
    });
  } catch (error) {
    parseError.value =
      error?.response?.status === 409
        ? t('TECHNICAL_INCIDENTS.FORM.CONFLICT')
        : error?.response?.data?.error || error.message;
    useAlert(parseError.value);
  }
};
const loadMetadata = () => store.dispatch('technicalIncidents/fetchOptions');
const loadIncident = async () => {
  try {
    const incident = await store.dispatch(
      'technicalIncidents/show',
      route.params.incidentId
    );
    if (componentActive.value) {
      hydrate(incident);
      incidentLoaded.value = true;
      incidentLoadError.value = false;
    }
  } catch {
    if (componentActive.value) incidentLoadError.value = true;
  }
};
const retryMetadata = async () => {
  metadataRequested.value = true;
  parseError.value = '';
  try {
    await loadMetadata();
    if (isEditing.value && !incidentLoaded.value) await loadIncident();
  } catch {
    // The store exposes the localized retry state without turning the error into an empty catalog.
  }
};

onMounted(async () => {
  metadataRequested.value = true;
  try {
    await loadMetadata();
    if (isEditing.value) await loadIncident();
  } catch {
    // Loading and error details are rendered from the store state.
  }
});
onBeforeUnmount(() => {
  componentActive.value = false;
});
</script>

<template>
  <main class="h-full overflow-auto bg-n-background p-4 md:p-8">
    <div class="mx-auto max-w-5xl">
      <h1 class="mb-6 text-2xl font-semibold text-n-slate-12">
        {{
          isEditing
            ? t('TECHNICAL_INCIDENTS.EDIT')
            : t('TECHNICAL_INCIDENTS.NEW')
        }}
      </h1>

      <div
        v-if="!metadataRequested || uiFlags.fetchingOptions"
        role="status"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-8 text-center text-n-slate-11"
      >
        {{ t('TECHNICAL_INCIDENTS.FORM.LOADING_OPTIONS') }}
      </div>
      <div
        v-else-if="uiFlags.optionsError"
        role="alert"
        class="grid justify-items-start gap-3 rounded-xl border border-n-ruby-7 bg-n-ruby-3 p-5 text-n-ruby-11"
      >
        <p>{{ t('TECHNICAL_INCIDENTS.FORM.OPTIONS_ERROR') }}</p>
        <button
          type="button"
          class="rounded-lg border border-n-ruby-7 px-3 py-2 text-sm"
          @click="retryMetadata"
        >
          {{ t('TECHNICAL_INCIDENTS.FORM.RETRY') }}
        </button>
      </div>
      <div
        v-else-if="metadataEmpty"
        role="alert"
        class="rounded-xl border border-n-amber-7 bg-n-amber-3 p-5 text-n-amber-11"
      >
        {{ t('TECHNICAL_INCIDENTS.FORM.OPTIONS_EMPTY') }}
      </div>
      <div
        v-else-if="incidentLoadError"
        role="alert"
        class="grid justify-items-start gap-3 rounded-xl border border-n-ruby-7 bg-n-ruby-3 p-5 text-n-ruby-11"
      >
        <p>{{ t('TECHNICAL_INCIDENTS.FORM.INCIDENT_LOAD_ERROR') }}</p>
        <button
          type="button"
          class="rounded-lg border border-n-ruby-7 px-3 py-2 text-sm"
          @click="loadIncident"
        >
          {{ t('TECHNICAL_INCIDENTS.FORM.RETRY') }}
        </button>
      </div>

      <form v-else class="grid gap-6" novalidate @submit.prevent="save">
        <section
          class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5 md:grid-cols-2"
        >
          <label class="grid gap-1 md:col-span-2">
            <span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.TITLE')
            }}</span>
            <input
              v-model="form.title"
              required
              maxlength="200"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            />
          </label>
          <label class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.TYPE')
            }}</span>
            <select
              v-model="form.incident_type"
              required
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            >
              <option
                v-for="option in options.incident_types"
                :key="option.value"
                :value="option.value"
              >
                {{ catalogLabel(option, t) }}
              </option>
            </select>
          </label>
          <label class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.SEVERITY')
            }}</span>
            <select
              v-model="form.severity"
              required
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            >
              <option
                v-for="option in options.severities"
                :key="option.value"
                :value="option.value"
              >
                {{ catalogLabel(option, t) }}
              </option>
            </select>
          </label>
          <label class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.PRIORITY')
            }}</span>
            <input
              v-model.number="form.priority"
              required
              type="number"
              min="0"
              max="100"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            />
          </label>
          <label class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.ACTION')
            }}</span>
            <select
              v-model="form.action"
              required
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            >
              <option
                v-for="option in options.actions"
                :key="option.value"
                :value="option.value"
              >
                {{ catalogLabel(option, t) }}
              </option>
            </select>
            <span v-if="selectedAction" class="text-xs text-n-slate-10">
              {{ actionDescription(selectedAction) }}
            </span>
          </label>
          <CatalogMultiSelect
            v-model="form.problem_types"
            :options="options.problem_types"
            :label="t('TECHNICAL_INCIDENTS.FORM.PROBLEMS')"
            input-id="incident-problem-types"
          />
          <CatalogMultiSelect
            v-model="form.affected_services"
            :options="options.affected_services"
            :label="t('TECHNICAL_INCIDENTS.FORM.SERVICES')"
            input-id="incident-services"
          />
        </section>

        <section
          class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5 md:grid-cols-2"
        >
          <label
            v-for="fieldName in [
              'starts_at',
              'expires_at',
              'review_at',
              'estimated_resolution_at',
            ]"
            :key="fieldName"
            class="grid gap-1"
          >
            <span class="text-sm font-medium text-n-slate-12">{{
              dateFieldLabel(fieldName)
            }}</span>
            <input
              v-model="form[fieldName]"
              type="datetime-local"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            />
          </label>
        </section>

        <section
          class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5"
        >
          <label class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.MESSAGE')
            }}</span>
            <textarea
              v-model="form.customer_message"
              maxlength="4000"
              rows="6"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 font-mono text-sm text-n-slate-12"
            />
          </label>
          <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-4">
            <p class="mb-2 text-xs font-semibold uppercase text-n-slate-10">
              {{ t('TECHNICAL_INCIDENTS.FORM.PREVIEW') }}
            </p>
            <p class="whitespace-pre-wrap text-sm text-n-slate-12">
              {{ preview }}
            </p>
          </div>
          <label class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.INTERNAL_NOTE')
            }}</span>
            <textarea
              v-model="form.internal_note"
              maxlength="10000"
              rows="4"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12"
            />
          </label>
        </section>

        <section
          class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-lg font-semibold text-n-slate-12">
              {{ t('TECHNICAL_INCIDENTS.FORM.SCOPES') }}
            </h2>
            <button
              type="button"
              class="rounded-lg border border-n-strong px-3 py-2 text-sm text-n-slate-12"
              @click="addGroup"
            >
              {{ t('TECHNICAL_INCIDENTS.FORM.ADD_GROUP') }}
            </button>
          </div>
          <div
            v-if="!form.scope_groups_attributes.some(group => !group._destroy)"
            class="rounded-lg border border-dashed border-n-strong p-5 text-sm text-n-slate-11"
          >
            {{ t('TECHNICAL_INCIDENTS.FORM.NO_SCOPE_GROUPS') }}
          </div>
          <div
            v-for="(group, groupIndex) in form.scope_groups_attributes"
            v-show="!group._destroy"
            :key="group.id || groupIndex"
            class="grid gap-3 rounded-lg border border-n-weak p-4"
          >
            <div class="flex items-center justify-between">
              <p class="text-xs font-semibold uppercase text-n-slate-10">
                {{
                  t('TECHNICAL_INCIDENTS.FORM.GROUP', {
                    number: groupIndex + 1,
                  })
                }}
              </p>
              <button
                type="button"
                class="text-sm text-n-ruby-11"
                @click="removeGroup(group)"
              >
                {{ t('TECHNICAL_INCIDENTS.FORM.REMOVE_GROUP') }}
              </button>
            </div>
            <ScopeCriterionEditor
              v-for="(criterion, criterionIndex) in group.criteria_attributes"
              v-show="!criterion._destroy"
              :key="criterion.id || criterionIndex"
              v-model:criterion="group.criteria_attributes[criterionIndex]"
              :fields="options.scope_fields"
              :operators="options.scope_operators"
              :used-types="
                group.criteria_attributes
                  .filter(item => !item._destroy)
                  .map(item => item.criterion_type)
              "
              :input-id="`scope-${groupIndex}-${criterionIndex}`"
              @remove="removeCriterion(group, criterion)"
            />
            <p
              v-if="
                !group.criteria_attributes.some(
                  criterion => !criterion._destroy
                )
              "
              class="text-sm text-n-ruby-11"
            >
              {{ t('TECHNICAL_INCIDENTS.FORM.NO_SCOPE_CRITERIA') }}
            </p>
            <button
              type="button"
              class="justify-self-start text-sm font-medium text-n-brand"
              @click="addCriterion(group)"
            >
              {{ t('TECHNICAL_INCIDENTS.FORM.ADD_CRITERION') }}
            </button>
          </div>
        </section>

        <div
          v-if="attemptedSubmit && formErrors.length"
          role="alert"
          class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
        >
          <p class="font-medium">
            {{ t('TECHNICAL_INCIDENTS.FORM.VALIDATION_SUMMARY') }}
          </p>
          <ul class="mt-2 list-disc pl-5">
            <li v-for="error in formErrors" :key="error">
              {{ validationMessage(error) }}
            </li>
          </ul>
        </div>
        <p
          v-if="parseError"
          role="alert"
          class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
        >
          {{ parseError }}
        </p>
        <div class="flex justify-end gap-3">
          <router-link
            :to="{ name: 'technical_incidents_index' }"
            class="rounded-lg border border-n-strong px-4 py-2 text-sm text-n-slate-12"
          >
            {{ t('TECHNICAL_INCIDENTS.CANCEL') }}
          </router-link>
          <button
            type="submit"
            :disabled="!canSave"
            class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
          >
            {{
              uiFlags.saving
                ? t('TECHNICAL_INCIDENTS.SAVING')
                : t('TECHNICAL_INCIDENTS.SAVE')
            }}
          </button>
        </div>
      </form>
    </div>
  </main>
</template>
