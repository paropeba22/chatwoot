<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import TechnicalIncidentsAPI from 'dashboard/api/technicalIncidents';
import { useAlert } from 'dashboard/composables';
import { usePolicy } from 'dashboard/composables/usePolicy';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { checkPermissions } = usePolicy();
const history = ref([]);
const conversations = ref([]);
const evaluations = ref([]);
const estimatedResolutionAt = ref('');
const expiresAt = ref('');
const feedbackSelections = ref({});
const activeTab = ref('information');
const incident = computed(
  () => store.getters['technicalIncidents/getCurrentTechnicalIncident']
);
const canUpdate = computed(() =>
  checkPermissions(['administrator', 'technical_incident_update'])
);
const canUpdateEta = computed(() =>
  checkPermissions([
    'administrator',
    'technical_incident_update',
    'technical_incident_update_eta',
  ])
);
const canResolve = computed(() =>
  checkPermissions(['administrator', 'technical_incident_resolve'])
);
const canArchive = computed(() =>
  checkPermissions(['administrator', 'technical_incident_archive'])
);
const canAudit = computed(() =>
  checkPermissions(['administrator', 'technical_incident_audit'])
);

const refresh = async () => {
  const id = route.params.incidentId;
  await store.dispatch('technicalIncidents/show', id);
  [history.value, conversations.value, evaluations.value] = await Promise.all([
    canAudit.value
      ? TechnicalIncidentsAPI.history(id).then(response => response.data)
      : Promise.resolve([]),
    TechnicalIncidentsAPI.conversations(id).then(response => response.data),
    canAudit.value
      ? TechnicalIncidentsAPI.evaluations(id).then(response => response.data)
      : Promise.resolve([]),
  ]);
  estimatedResolutionAt.value =
    incident.value.estimated_resolution_at?.slice(0, 16) || '';
  expiresAt.value = incident.value.expires_at?.slice(0, 16) || '';
};
const transition = async (status, attributes = {}) => {
  try {
    await store.dispatch('technicalIncidents/transition', {
      id: incident.value.id,
      status,
      attributes,
    });
    await refresh();
  } catch (error) {
    useAlert(error?.response?.data?.reason_code || error.message);
  }
};
const updateSchedule = async () => {
  try {
    await store.dispatch('technicalIncidents/update', {
      id: incident.value.id,
      payload: {
        estimated_resolution_at: estimatedResolutionAt.value || null,
        expires_at: expiresAt.value || null,
        lock_version: incident.value.lock_version,
      },
    });
    await refresh();
  } catch (error) {
    useAlert(error?.response?.data?.error || error.message);
  }
};
const submitFeedback = async evaluation => {
  const feedback = feedbackSelections.value[evaluation.opaque_id];
  if (!feedback) return;

  await TechnicalIncidentsAPI.feedback(evaluation.opaque_id, {
    account_id: route.params.accountId,
    feedback,
  });
  await refresh();
};
const formatConversation = item =>
  `#${item.conversation_display_id} · ${item.contract_reference || '—'} · v${item.notification_version}`;
const formatEvaluationTitle = item =>
  `${item.status} · ${item.match_source || '—'}`;
const formatEvaluationMeta = item =>
  `${item.reason_code || '—'} · ${item.latency_ms || 0}ms`;
const archive = async () => {
  await store.dispatch('technicalIncidents/delete', incident.value.id);
  router.push({ name: 'technical_incidents_index' });
};

onMounted(refresh);
</script>

<template>
  <main v-if="incident" class="h-full overflow-auto bg-n-background p-4 md:p-8">
    <div class="mx-auto max-w-6xl">
      <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <p class="text-xs font-semibold uppercase text-n-slate-10">
            #{{ incident.id }} · {{ incident.status }}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-n-slate-12">
            {{ incident.title }}
          </h1>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ incident.severity }} · {{ incident.incident_type }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <router-link
            v-if="canUpdate"
            :to="{
              name: 'technical_incidents_edit',
              params: { incidentId: incident.id },
            }"
            class="rounded-lg border border-n-strong px-3 py-2 text-sm"
            >{{ t('TECHNICAL_INCIDENTS.EDIT') }}</router-link
          >
          <button
            v-if="canUpdate && ['draft', 'scheduled'].includes(incident.status)"
            type="button"
            class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white"
            @click="transition('active')"
          >
            {{ t('TECHNICAL_INCIDENTS.ACTIONS.ACTIVATE') }}
          </button>
          <button
            v-if="canUpdate && incident.status === 'active'"
            type="button"
            class="rounded-lg border border-n-strong px-3 py-2 text-sm"
            @click="transition('monitoring')"
          >
            {{ t('TECHNICAL_INCIDENTS.ACTIONS.MONITOR') }}
          </button>
          <button
            v-if="
              canResolve && ['active', 'monitoring'].includes(incident.status)
            "
            type="button"
            class="rounded-lg border border-n-strong px-3 py-2 text-sm"
            @click="transition('resolved')"
          >
            {{ t('TECHNICAL_INCIDENTS.ACTIONS.RESOLVE') }}
          </button>
          <button
            v-if="
              canUpdate &&
              ['draft', 'scheduled', 'active', 'monitoring'].includes(
                incident.status
              )
            "
            type="button"
            class="rounded-lg border border-n-strong px-3 py-2 text-sm"
            @click="transition('cancelled')"
          >
            {{ t('TECHNICAL_INCIDENTS.ACTIONS.CANCEL') }}
          </button>
          <button
            v-if="
              canUpdate &&
              ['resolved', 'expired', 'cancelled'].includes(incident.status)
            "
            type="button"
            class="rounded-lg border border-n-strong px-3 py-2 text-sm"
            @click="transition('active', { expires_at: expiresAt })"
          >
            {{ t('TECHNICAL_INCIDENTS.ACTIONS.REOPEN') }}
          </button>
          <button
            v-if="canArchive"
            type="button"
            class="rounded-lg border border-n-ruby-7 px-3 py-2 text-sm text-n-ruby-11"
            @click="archive"
          >
            {{ t('TECHNICAL_INCIDENTS.ACTIONS.ARCHIVE') }}
          </button>
        </div>
      </header>

      <nav
        class="mb-4 flex gap-1 overflow-x-auto border-b border-n-weak"
        :aria-label="t('TECHNICAL_INCIDENTS.DETAIL_TABS')"
      >
        <button
          v-for="tab in [
            'information',
            'history',
            'conversations',
            'evaluations',
          ]"
          :key="tab"
          type="button"
          class="border-b-2 px-4 py-2 text-sm"
          :class="
            activeTab === tab
              ? 'border-n-brand text-n-brand'
              : 'border-transparent text-n-slate-11'
          "
          @click="activeTab = tab"
        >
          {{ t(`TECHNICAL_INCIDENTS.TABS.${tab.toUpperCase()}`) }}
        </button>
      </nav>

      <section
        v-if="activeTab === 'information'"
        class="grid gap-4 md:grid-cols-2"
      >
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-5">
          <h2 class="mb-3 font-semibold text-n-slate-12">
            {{ t('TECHNICAL_INCIDENTS.MESSAGE') }}
          </h2>
          <p class="whitespace-pre-wrap text-sm text-n-slate-12">
            {{ incident.customer_message || '—' }}
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-5">
          <h2 class="mb-3 font-semibold text-n-slate-12">
            {{ t('TECHNICAL_INCIDENTS.INTERNAL_NOTE') }}
          </h2>
          <p class="whitespace-pre-wrap text-sm text-n-slate-12">
            {{ incident.internal_note || '—' }}
          </p>
        </div>
        <div
          class="rounded-xl border border-n-weak bg-n-solid-1 p-5 md:col-span-2"
        >
          <h2 class="mb-3 font-semibold text-n-slate-12">
            {{ t('TECHNICAL_INCIDENTS.SCOPES') }}
          </h2>
          <pre
            class="overflow-auto whitespace-pre-wrap text-xs text-n-slate-11"
            >{{ JSON.stringify(incident.scope_groups, null, 2) }}</pre
          >
        </div>
        <div
          v-if="incident.conflicts?.length"
          class="rounded-xl border border-n-amber-7 bg-n-amber-3 p-5 md:col-span-2"
        >
          <h2 class="mb-2 font-semibold text-n-amber-11">
            {{ t('TECHNICAL_INCIDENTS.CONFLICTS') }}
          </h2>
          <p
            v-for="conflict in incident.conflicts"
            :key="conflict.incident_id"
            class="text-sm text-n-amber-11"
          >
            #{{ conflict.incident_id }} {{ conflict.title }} —
            {{ conflict.reasons.join(', ') }}
          </p>
        </div>
        <div
          v-if="canUpdateEta"
          class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-5 md:col-span-2 md:grid-cols-[1fr_1fr_auto]"
        >
          <label class="grid gap-1 text-sm text-n-slate-12"
            >{{ t('TECHNICAL_INCIDENTS.FORM.ESTIMATED_RESOLUTION_AT')
            }}<input
              v-model="estimatedResolutionAt"
              type="datetime-local"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
          /></label>
          <label class="grid gap-1 text-sm text-n-slate-12"
            >{{ t('TECHNICAL_INCIDENTS.FORM.EXPIRES_AT')
            }}<input
              v-model="expiresAt"
              type="datetime-local"
              class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2"
          /></label>
          <button
            type="button"
            class="self-end rounded-lg bg-n-brand px-3 py-2 text-sm text-white"
            @click="updateSchedule"
          >
            {{ t('TECHNICAL_INCIDENTS.ACTIONS.UPDATE_SCHEDULE') }}
          </button>
        </div>
        <dl
          class="grid grid-cols-2 gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-5 text-sm md:col-span-2 md:grid-cols-4"
        >
          <div v-for="(value, key) in incident.metrics" :key="key">
            <dt class="text-n-slate-10">{{ key }}</dt>
            <dd class="text-lg font-semibold text-n-slate-12">{{ value }}</dd>
          </div>
        </dl>
      </section>

      <section v-else class="rounded-xl border border-n-weak bg-n-solid-1">
        <div v-if="activeTab === 'history'">
          <article
            v-for="item in history"
            :key="item.id"
            class="border-b border-n-weak p-4 text-sm"
          >
            <p class="font-medium text-n-slate-12">{{ item.action }}</p>
            <p class="text-n-slate-10">
              {{ item.created_at }} · {{ item.origin }}
            </p>
          </article>
        </div>
        <div v-else-if="activeTab === 'conversations'">
          <article
            v-for="item in conversations"
            :key="item.id"
            class="border-b border-n-weak p-4 text-sm text-n-slate-12"
          >
            {{ formatConversation(item) }}
          </article>
        </div>
        <div v-else-if="canAudit">
          <article
            v-for="item in evaluations"
            :key="item.opaque_id"
            class="grid gap-3 border-b border-n-weak p-4 text-sm md:grid-cols-[1fr_auto]"
          >
            <div>
              <p class="font-medium text-n-slate-12">
                {{ formatEvaluationTitle(item) }}
              </p>
              <p class="text-n-slate-10">
                {{ formatEvaluationMeta(item) }}
              </p>
            </div>
            <div class="flex gap-2">
              <select
                v-model="feedbackSelections[item.opaque_id]"
                class="rounded-lg border border-n-strong bg-n-alpha-1 px-2 py-1"
              >
                <option value="">
                  {{ t('TECHNICAL_INCIDENTS.FEEDBACK.SELECT') }}
                </option>
                <option
                  v-for="type in [
                    'correct_match',
                    'false_positive',
                    'false_negative',
                    'wrong_contract',
                    'wrong_category',
                    'duplicate_message',
                    'other',
                  ]"
                  :key="type"
                  :value="type"
                >
                  {{ type }}
                </option>
              </select>
              <button
                type="button"
                class="rounded-lg border border-n-strong px-2 py-1"
                @click="submitFeedback(item)"
              >
                {{ t('TECHNICAL_INCIDENTS.FEEDBACK.SEND') }}
              </button>
            </div>
          </article>
        </div>
      </section>
    </div>
  </main>
</template>
