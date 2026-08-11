<script setup>
import { computed, onMounted, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { catalogLabel } from '../helpers/formCatalog';

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const { checkPermissions } = usePolicy();
const canCreate = computed(() =>
  checkPermissions(['administrator', 'technical_incident_create'])
);
const filters = reactive({
  q: '',
  bucket: 'active',
  status: '',
  severity: '',
  category: '',
  service: '',
  scope_type: '',
  page: 1,
});

const records = computed(
  () => store.getters['technicalIncidents/getTechnicalIncidents']
);
const meta = computed(
  () => store.getters['technicalIncidents/getTechnicalIncidentMeta']
);
const options = computed(
  () => store.getters['technicalIncidents/getTechnicalIncidentOptions']
);
const uiFlags = computed(
  () => store.getters['technicalIncidents/getTechnicalIncidentUIFlags']
);
const fetchRecords = () =>
  store.dispatch('technicalIncidents/fetch', { ...filters });
const openIncident = incident =>
  router.push({
    name: 'technical_incidents_show',
    params: { incidentId: incident.id },
  });
const bucketLabel = bucket => {
  const labels = {
    active: t('TECHNICAL_INCIDENTS.BUCKETS.ACTIVE'),
    scheduled: t('TECHNICAL_INCIDENTS.BUCKETS.SCHEDULED'),
    history: t('TECHNICAL_INCIDENTS.BUCKETS.HISTORY'),
  };
  return labels[bucket];
};

onMounted(async () => {
  await Promise.allSettled([
    store.dispatch('technicalIncidents/fetchOptions'),
    fetchRecords(),
  ]);
});
</script>

<template>
  <main class="flex h-full flex-col overflow-auto bg-n-background p-4 md:p-8">
    <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div>
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ t('TECHNICAL_INCIDENTS.TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('TECHNICAL_INCIDENTS.DESCRIPTION') }}
        </p>
      </div>
      <router-link
        v-if="canCreate"
        :to="{ name: 'technical_incidents_new' }"
        class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white hover:bg-n-brand/90"
      >
        {{ t('TECHNICAL_INCIDENTS.NEW') }}
      </router-link>
    </header>

    <nav
      class="mb-4 flex gap-2"
      :aria-label="t('TECHNICAL_INCIDENTS.BUCKETS.LABEL')"
    >
      <button
        v-for="bucket in ['active', 'scheduled', 'history']"
        :key="bucket"
        type="button"
        class="rounded-lg px-3 py-2 text-sm"
        :class="
          filters.bucket === bucket
            ? 'bg-n-brand text-white'
            : 'border border-n-strong text-n-slate-12'
        "
        @click="
          filters.bucket = bucket;
          filters.page = 1;
          fetchRecords();
        "
      >
        {{ bucketLabel(bucket) }}
      </button>
    </nav>

    <section
      class="mb-4 grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 md:grid-cols-3 xl:grid-cols-6"
      :aria-label="t('TECHNICAL_INCIDENTS.FILTERS')"
    >
      <input
        v-model="filters.q"
        class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
        :placeholder="t('TECHNICAL_INCIDENTS.SEARCH')"
        @keyup.enter="fetchRecords"
      />
      <select
        v-model="filters.status"
        class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
      >
        <option value="">{{ t('TECHNICAL_INCIDENTS.ALL_STATUSES') }}</option>
        <option
          v-for="status in options.statuses"
          :key="status.value"
          :value="status.value"
        >
          {{ catalogLabel(status, t) }}
        </option>
      </select>
      <select
        v-model="filters.severity"
        class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
      >
        <option value="">{{ t('TECHNICAL_INCIDENTS.ALL_SEVERITIES') }}</option>
        <option
          v-for="severity in options.severities"
          :key="severity.value"
          :value="severity.value"
        >
          {{ catalogLabel(severity, t) }}
        </option>
      </select>
      <select
        v-model="filters.category"
        class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
      >
        <option value="">{{ t('TECHNICAL_INCIDENTS.ALL_CATEGORIES') }}</option>
        <option
          v-for="category in options.incident_types"
          :key="category.value"
          :value="category.value"
        >
          {{ catalogLabel(category, t) }}
        </option>
      </select>
      <select
        v-model="filters.scope_type"
        class="rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12"
      >
        <option value="">{{ t('TECHNICAL_INCIDENTS.ALL_SCOPES') }}</option>
        <option
          v-for="scope in options.scope_fields"
          :key="scope.value"
          :value="scope.value"
        >
          {{ catalogLabel(scope, t) }}
        </option>
      </select>
      <button
        type="button"
        class="rounded-lg border border-n-strong px-4 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2"
        @click="fetchRecords"
      >
        {{ t('TECHNICAL_INCIDENTS.APPLY') }}
      </button>
    </section>

    <div
      v-if="uiFlags.fetching"
      class="rounded-xl border border-n-weak p-8 text-center text-n-slate-11"
    >
      {{ t('TECHNICAL_INCIDENTS.LOADING') }}
    </div>
    <div
      v-else-if="!records.length"
      class="rounded-xl border border-dashed border-n-strong p-12 text-center text-n-slate-11"
    >
      {{ t('TECHNICAL_INCIDENTS.EMPTY') }}
    </div>
    <div v-else class="overflow-x-auto rounded-xl border border-n-weak">
      <table class="w-full border-collapse text-left text-sm">
        <thead class="bg-n-alpha-2 text-n-slate-11">
          <tr>
            <th class="p-3">{{ t('TECHNICAL_INCIDENTS.TABLE.INCIDENT') }}</th>
            <th class="p-3">{{ t('TECHNICAL_INCIDENTS.TABLE.STATUS') }}</th>
            <th class="p-3">{{ t('TECHNICAL_INCIDENTS.TABLE.SEVERITY') }}</th>
            <th class="p-3">{{ t('TECHNICAL_INCIDENTS.TABLE.SCOPE') }}</th>
            <th class="p-3">{{ t('TECHNICAL_INCIDENTS.TABLE.ETA') }}</th>
            <th class="p-3">
              {{ t('TECHNICAL_INCIDENTS.TABLE.CONVERSATIONS') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="incident in records"
            :key="incident.id"
            tabindex="0"
            class="cursor-pointer border-t border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            @click="openIncident(incident)"
            @keyup.enter="openIncident(incident)"
          >
            <td class="p-3">
              <p class="font-medium">{{ incident.title }}</p>
              <p class="text-xs text-n-slate-10">
                {{ incident.incident_type }}
              </p>
            </td>
            <td class="p-3">{{ incident.status }}</td>
            <td class="p-3">{{ incident.severity }}</td>
            <td class="p-3">
              {{ incident.affected_services.join(', ') || '—' }}
            </td>
            <td class="p-3">{{ incident.estimated_resolution_at || '—' }}</td>
            <td class="p-3">{{ incident.conversation_links_count }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <nav
      v-if="meta.total_entries > meta.per_page"
      class="mt-4 flex items-center justify-end gap-3"
      :aria-label="t('TECHNICAL_INCIDENTS.PAGINATION')"
    >
      <button
        type="button"
        class="rounded border border-n-strong px-3 py-1 disabled:opacity-50"
        :disabled="filters.page <= 1"
        @click="
          filters.page -= 1;
          fetchRecords();
        "
      >
        {{ t('TECHNICAL_INCIDENTS.PREVIOUS') }}
      </button>
      <span class="text-sm text-n-slate-11">{{ filters.page }}</span>
      <button
        type="button"
        class="rounded border border-n-strong px-3 py-1 disabled:opacity-50"
        :disabled="filters.page * meta.per_page >= meta.total_entries"
        @click="
          filters.page += 1;
          fetchRecords();
        "
      >
        {{ t('TECHNICAL_INCIDENTS.NEXT') }}
      </button>
    </nav>
  </main>
</template>
