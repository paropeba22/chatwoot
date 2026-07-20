<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const parseError = ref('');
const isEditing = computed(() => Boolean(route.params.incidentId));
const options = computed(
  () => store.getters['technicalIncidents/getTechnicalIncidentOptions']
);
const uiFlags = computed(
  () => store.getters['technicalIncidents/getTechnicalIncidentUIFlags']
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
  scope_groups_attributes: [
    {
      position: 0,
      criteria_attributes: [
        { criterion_type: 'general', operator: 'in', values_text: '[]' },
      ],
    },
  ],
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

const hydrate = incident =>
  Object.assign(form, {
    ...incident,
    starts_at: incident.starts_at?.slice(0, 16) || '',
    expires_at: incident.expires_at?.slice(0, 16) || '',
    review_at: incident.review_at?.slice(0, 16) || '',
    estimated_resolution_at:
      incident.estimated_resolution_at?.slice(0, 16) || '',
    scope_groups_attributes: incident.scope_groups.map(group => ({
      id: group.id,
      position: group.position,
      criteria_attributes: group.criteria.map(criterion => ({
        ...criterion,
        values_text: JSON.stringify(criterion.values, null, 2),
      })),
    })),
  });
const addGroup = () =>
  form.scope_groups_attributes.push({
    position: form.scope_groups_attributes.length,
    criteria_attributes: [
      { criterion_type: 'contract_id', operator: 'in', values_text: '[]' },
    ],
  });
const addCriterion = group =>
  group.criteria_attributes.push({
    criterion_type: 'contract_id',
    operator: 'in',
    values_text: '[]',
  });
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
  scope_groups_attributes: form.scope_groups_attributes.map(group => ({
    id: group.id,
    position: group.position,
    _destroy: Reflect.get(group, '_destroy'),
    criteria_attributes: group.criteria_attributes.map(criterion => ({
      id: criterion.id,
      criterion_type: criterion.criterion_type,
      operator: criterion.operator,
      values: JSON.parse(criterion.values_text || '[]'),
      _destroy: Reflect.get(criterion, '_destroy'),
    })),
  })),
});
const save = async () => {
  parseError.value = '';
  if (unknownVariables.value.length) {
    parseError.value = t('TECHNICAL_INCIDENTS.FORM.UNKNOWN_VARIABLE');
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

onMounted(async () => {
  await store.dispatch('technicalIncidents/fetchOptions');
  if (isEditing.value)
    hydrate(
      await store.dispatch('technicalIncidents/show', route.params.incidentId)
    );
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
      <form class="grid gap-6" @submit.prevent="save">
        <section
          class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5 md:grid-cols-2"
        >
          <label class="grid gap-1 md:col-span-2"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.TITLE')
            }}</span
            ><input
              v-model="form.title"
              required
              maxlength="200"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
          /></label>
          <label class="grid gap-1"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.TYPE')
            }}</span
            ><select
              v-model="form.incident_type"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
            >
              <option
                v-for="value in options.incident_types"
                :key="value"
                :value="value"
              >
                {{ value }}
              </option>
            </select></label
          >
          <label class="grid gap-1"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.SEVERITY')
            }}</span
            ><select
              v-model="form.severity"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
            >
              <option
                v-for="value in options.severities"
                :key="value"
                :value="value"
              >
                {{ value }}
              </option>
            </select></label
          >
          <label class="grid gap-1"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.PRIORITY')
            }}</span
            ><input
              v-model.number="form.priority"
              type="number"
              min="0"
              max="100"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
          /></label>
          <label class="grid gap-1"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.ACTION')
            }}</span
            ><select
              v-model="form.action"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
            >
              <option
                v-for="value in options.actions"
                :key="value"
                :value="value"
              >
                {{ value }}
              </option>
            </select></label
          >
          <label class="grid gap-1"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.PROBLEMS')
            }}</span
            ><select
              v-model="form.problem_types"
              multiple
              class="min-h-32 rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
            >
              <option
                v-for="value in options.problem_types"
                :key="value"
                :value="value"
              >
                {{ value }}
              </option>
            </select></label
          >
          <label class="grid gap-1"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.SERVICES')
            }}</span
            ><select
              v-model="form.affected_services"
              multiple
              class="min-h-32 rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
            >
              <option
                v-for="value in options.service_keys"
                :key="value"
                :value="value"
              >
                {{ value }}
              </option>
            </select></label
          >
        </section>

        <section
          class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5 md:grid-cols-2"
        >
          <label
            v-for="field in [
              'starts_at',
              'expires_at',
              'review_at',
              'estimated_resolution_at',
            ]"
            :key="field"
            class="grid gap-1"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t(`TECHNICAL_INCIDENTS.FORM.${field.toUpperCase()}`)
            }}</span
            ><input
              v-model="form[field]"
              type="datetime-local"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
          /></label>
        </section>

        <section
          class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5"
        >
          <label class="grid gap-1"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.MESSAGE')
            }}</span
            ><textarea
              v-model="form.customer_message"
              maxlength="4000"
              rows="6"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 font-mono text-sm"
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
          <label class="grid gap-1"
            ><span class="text-sm font-medium text-n-slate-12">{{
              t('TECHNICAL_INCIDENTS.FORM.INTERNAL_NOTE')
            }}</span
            ><textarea
              v-model="form.internal_note"
              maxlength="10000"
              rows="4"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
            />
          </label>
        </section>

        <section
          class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5"
        >
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold text-n-slate-12">
              {{ t('TECHNICAL_INCIDENTS.FORM.SCOPES') }}
            </h2>
            <button
              type="button"
              class="rounded-lg border border-n-strong px-3 py-2 text-sm"
              @click="addGroup"
            >
              {{ t('TECHNICAL_INCIDENTS.FORM.ADD_GROUP') }}
            </button>
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
                {{ t('TECHNICAL_INCIDENTS.REMOVE') }}
              </button>
            </div>
            <div
              v-for="(criterion, criterionIndex) in group.criteria_attributes"
              v-show="!criterion._destroy"
              :key="criterion.id || criterionIndex"
              class="grid gap-3 md:grid-cols-[14rem_1fr_auto]"
            >
              <select
                v-model="criterion.criterion_type"
                class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
              >
                <option
                  v-for="value in options.scope_types"
                  :key="value"
                  :value="value"
                >
                  {{ value }}
                </option>
              </select>
              <textarea
                v-model="criterion.values_text"
                rows="3"
                class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 font-mono text-xs"
                :aria-label="t('TECHNICAL_INCIDENTS.FORM.SCOPE_VALUES')"
              />
              <button
                type="button"
                class="text-sm text-n-ruby-11"
                @click="removeCriterion(group, criterion)"
              >
                {{ t('TECHNICAL_INCIDENTS.REMOVE') }}
              </button>
            </div>
            <button
              type="button"
              class="justify-self-start text-sm font-medium text-n-brand"
              @click="addCriterion(group)"
            >
              {{ t('TECHNICAL_INCIDENTS.FORM.ADD_CRITERION') }}
            </button>
          </div>
        </section>

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
            class="rounded-lg border border-n-strong px-4 py-2 text-sm"
          >
            {{ t('TECHNICAL_INCIDENTS.CANCEL') }}
          </router-link>
          <button
            type="submit"
            :disabled="uiFlags.saving"
            class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
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
