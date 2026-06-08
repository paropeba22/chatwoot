<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import SgpAPI from 'dashboard/api/integrations/sgp';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  contact: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();
const store = useStore();
const isEditingDocument = ref(false);
const isLoading = ref(false);
const activeAction = ref('');
const documentValue = ref('');
const statusMessage = ref('');
const statusType = ref('');

const customAttributes = computed(() => props.contact?.custom_attributes || {});
const legacyAttributes = computed(
  () => props.contact?.additional_attributes || {}
);

const attributeValue = (customKey, legacyKey) =>
  customAttributes.value[customKey] ??
  legacyAttributes.value[legacyKey] ??
  null;

const sgpData = computed(() => ({
  cpfCnpj: attributeValue('sgp_cpf_cnpj', 'cpf'),
  holderName: attributeValue('sgp_nome_titular', 'nome_titular'),
  contract: attributeValue('sgp_contrato', 'contrato'),
  contractStatus: attributeValue('sgp_status_contrato', 'status_contrato'),
  onu: attributeValue('sgp_onu', 'onu'),
  onuStatus: attributeValue('sgp_status_onu', 'status_onu'),
  plan: attributeValue('sgp_plano', 'plano_sgp'),
  invoiceStatus: attributeValue('sgp_fatura_status', 'fatura_status'),
  invoiceDueDate: attributeValue('sgp_fatura_vencimento', 'vencimento_fatura'),
  invoiceValue: attributeValue('sgp_fatura_valor', 'valor_fatura'),
  updatedAt: customAttributes.value.sgp_atualizado_em,
}));

const disabledActions = computed(() => [
  { key: 'pix', label: t('CONVERSATION.SGP.ACTIONS.PIX') },
  { key: 'barcode', label: t('CONVERSATION.SGP.ACTIONS.BARCODE') },
  { key: 'pdf', label: t('CONVERSATION.SGP.ACTIONS.PDF') },
]);

const digitsOnly = value => String(value || '').replace(/\D/g, '');

const calculateDigit = (digits, weights) => {
  const remainder = Array.from(digits).reduce(
    (sum, digit, index) => sum + Number(digit) * weights[index],
    0
  );
  const mod = remainder % 11;
  return mod < 2 ? 0 : 11 - mod;
};

const isValidCpf = value => {
  if (/^(\d)\1+$/.test(value)) return false;
  const first = calculateDigit(value.slice(0, 9), [10, 9, 8, 7, 6, 5, 4, 3, 2]);
  const second = calculateDigit(
    `${value.slice(0, 9)}${first}`,
    [11, 10, 9, 8, 7, 6, 5, 4, 3, 2]
  );
  return value.endsWith(`${first}${second}`);
};

const isValidCnpj = value => {
  if (/^(\d)\1+$/.test(value)) return false;
  const first = calculateDigit(
    value.slice(0, 12),
    [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
  );
  const second = calculateDigit(
    `${value.slice(0, 12)}${first}`,
    [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
  );
  return value.endsWith(`${first}${second}`);
};

const isValidDocument = value =>
  (value.length === 11 && isValidCpf(value)) ||
  (value.length === 14 && isValidCnpj(value));

const setStatus = (message, type) => {
  statusMessage.value = message;
  statusType.value = type;
};

const refreshContact = async () => {
  if (props.contact?.id) {
    await store.dispatch('contacts/show', { id: props.contact.id });
  }
};

const performAction = async (action, payload = {}) => {
  isLoading.value = true;
  activeAction.value = action;
  setStatus('', '');

  try {
    const { data } = await SgpAPI.perform(props.conversationId, {
      action,
      ...payload,
    });
    await refreshContact();
    setStatus(data.message || t('CONVERSATION.SGP.SUCCESS'), 'success');
    return data;
  } catch (error) {
    const data = error.response?.data || {};
    if (data.cpf_saved) await refreshContact();
    setStatus(
      data.message || t('CONVERSATION.SGP.ERRORS.SGP_UNAVAILABLE'),
      'error'
    );
    return data;
  } finally {
    isLoading.value = false;
    activeAction.value = '';
  }
};

const startEditDocument = () => {
  documentValue.value = sgpData.value.cpfCnpj || '';
  isEditingDocument.value = true;
  setStatus('', '');
};

const saveDocument = async () => {
  const document = digitsOnly(documentValue.value);
  if (!isValidDocument(document)) {
    setStatus(t('CONVERSATION.SGP.ERRORS.INVALID_DOCUMENT'), 'error');
    return;
  }

  const result = await performAction('consultar_sgp_por_cpf', {
    cpf_cnpj: document,
  });
  if (result.ok || result.cpf_saved) isEditingDocument.value = false;
};

const consultOnu = () => performAction('consultar_status_onu');

watch(
  () => props.contact?.id,
  () => {
    isEditingDocument.value = false;
    documentValue.value = '';
    setStatus('', '');
  }
);
</script>

<template>
  <section
    class="px-4 py-4 border-b border-n-weak bg-gradient-to-br from-n-blue-2/70 via-transparent to-n-teal-2/30"
    data-testid="sgp-panel"
  >
    <div class="flex items-start justify-between gap-3 mb-3">
      <div>
        <h3
          class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
        >
          <span class="i-lucide-shield-check size-4 text-n-blue-10" />
          {{ t('CONVERSATION.SGP.TITLE') }}
        </h3>
        <p v-if="sgpData.updatedAt" class="mt-1 text-[11px] text-n-slate-10">
          {{ t('CONVERSATION.SGP.UPDATED_AT', { value: sgpData.updatedAt }) }}
        </p>
      </div>
      <span
        v-if="isLoading"
        class="i-lucide-loader-circle size-4 text-n-blue-10 animate-spin"
      />
    </div>

    <div class="grid grid-cols-2 gap-2 mb-3">
      <div class="p-2.5 rounded-xl border border-n-weak bg-n-alpha-1">
        <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
          {{ t('CONVERSATION.SGP.FIELDS.CONTRACT') }}
        </p>
        <p class="mt-1 text-sm font-semibold text-n-slate-12 truncate">
          {{ sgpData.contract || sgpData.contractStatus || 'N/A' }}
        </p>
        <p
          v-if="sgpData.contract && sgpData.contractStatus"
          class="text-[11px] text-n-slate-10"
        >
          {{ sgpData.contractStatus }}
        </p>
      </div>
      <div class="p-2.5 rounded-xl border border-n-weak bg-n-alpha-1">
        <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
          {{ t('CONVERSATION.SGP.FIELDS.ONU') }}
        </p>
        <p class="mt-1 text-sm font-semibold text-n-slate-12 truncate">
          {{ sgpData.onuStatus || sgpData.onu || 'N/A' }}
        </p>
        <p
          v-if="sgpData.onu && sgpData.onuStatus"
          class="text-[11px] text-n-slate-10 truncate"
        >
          {{ sgpData.onu }}
        </p>
      </div>
      <div class="p-2.5 rounded-xl border border-n-weak bg-n-alpha-1">
        <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
          {{ t('CONVERSATION.SGP.FIELDS.PLAN') }}
        </p>
        <p class="mt-1 text-sm font-semibold text-n-slate-12 truncate">
          {{ sgpData.plan || 'N/A' }}
        </p>
      </div>
      <div class="p-2.5 rounded-xl border border-n-weak bg-n-alpha-1">
        <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
          {{ t('CONVERSATION.SGP.FIELDS.INVOICE') }}
        </p>
        <p class="mt-1 text-sm font-semibold text-n-slate-12 truncate">
          {{ sgpData.invoiceValue || 'N/A' }}
        </p>
        <p class="text-[11px] text-n-slate-10 truncate">
          {{ sgpData.invoiceDueDate || sgpData.invoiceStatus || '—' }}
        </p>
      </div>
    </div>

    <div
      v-if="sgpData.holderName"
      class="p-2.5 mb-2 rounded-xl border border-n-weak bg-n-alpha-1"
    >
      <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
        {{ t('CONVERSATION.SGP.FIELDS.HOLDER') }}
      </p>
      <p class="mt-1 text-sm font-semibold text-n-slate-12 truncate">
        {{ sgpData.holderName }}
      </p>
    </div>

    <div
      class="flex items-center justify-between p-2.5 mb-3 rounded-xl border border-n-weak bg-n-alpha-1"
    >
      <div class="flex-1 min-w-0 mr-2">
        <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
          {{ t('CONVERSATION.SGP.FIELDS.DOCUMENT') }}
        </p>
        <p
          v-if="!isEditingDocument"
          class="mt-1 text-sm font-semibold text-n-slate-12 truncate"
        >
          {{ sgpData.cpfCnpj || t('CONVERSATION.SGP.NOT_INFORMED') }}
        </p>
        <input
          v-else
          v-model="documentValue"
          type="text"
          inputmode="numeric"
          autocomplete="off"
          maxlength="18"
          class="w-full px-2.5 py-1 mt-1 text-sm outline-none rounded-lg bg-n-background border border-n-strong focus:border-n-blue-9"
          :placeholder="t('CONVERSATION.SGP.DOCUMENT_PLACEHOLDER')"
          :disabled="isLoading"
          data-testid="sgp-document-input"
        />
      </div>
      <button
        v-if="!isEditingDocument"
        class="text-xs font-medium text-n-blue-11 hover:text-n-blue-10"
        :disabled="isLoading"
        @click="startEditDocument"
      >
        {{ t('CONVERSATION.SGP.CHANGE') }}
      </button>
      <div v-else class="flex items-center gap-2">
        <button
          class="px-2.5 py-1 text-xs font-medium rounded-lg bg-n-teal-3 text-n-teal-11 disabled:opacity-50"
          :disabled="isLoading"
          @click="saveDocument"
        >
          {{ t('CONVERSATION.SGP.SAVE_AND_CONSULT') }}
        </button>
        <button
          class="text-xs text-n-slate-10 hover:text-n-slate-12"
          :disabled="isLoading"
          @click="isEditingDocument = false"
        >
          {{ t('CONVERSATION.SGP.CANCEL') }}
        </button>
      </div>
    </div>

    <p
      v-if="statusMessage"
      class="p-2 mb-3 text-xs rounded-lg"
      :class="
        statusType === 'success'
          ? 'bg-n-teal-3 text-n-teal-11'
          : 'bg-n-ruby-3 text-n-ruby-11'
      "
      role="status"
    >
      {{ statusMessage }}
    </p>

    <div class="grid grid-cols-3 gap-1.5">
      <button
        class="py-2 px-1 rounded-lg text-[11px] font-semibold border border-n-weak bg-n-alpha-1 text-n-slate-12 disabled:opacity-50"
        :disabled="isLoading || !sgpData.cpfCnpj"
        @click="consultOnu"
      >
        <span
          class="size-3 inline-block align-text-bottom mr-0.5"
          :class="
            activeAction === 'consultar_status_onu'
              ? 'i-lucide-loader-circle animate-spin'
              : 'i-lucide-radio-tower'
          "
        />
        {{ t('CONVERSATION.SGP.ACTIONS.ONU') }}
      </button>
      <button
        v-for="action in disabledActions"
        :key="action.key"
        class="py-2 px-1 rounded-lg text-[11px] font-semibold border border-n-weak bg-n-alpha-1 text-n-slate-9 cursor-not-allowed"
        disabled
      >
        {{ action.label }}
      </button>
      <button
        class="col-span-2 py-2 px-1 rounded-lg text-[11px] font-semibold border border-n-weak bg-n-alpha-1 text-n-slate-9 cursor-not-allowed"
        disabled
      >
        {{ t('CONVERSATION.SGP.ACTIONS.PAYMENT_PROMISE') }}
      </button>
    </div>
  </section>
</template>
