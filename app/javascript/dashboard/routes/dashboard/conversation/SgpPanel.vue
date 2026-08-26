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
const pendingFinancialAction = ref(null);
const selectedInvoiceId = ref('');
const showPromiseConfirmation = ref(false);

const customAttributes = computed(() => props.contact?.custom_attributes || {});
const legacyAttributes = computed(
  () => props.contact?.additional_attributes || {}
);

const attributeValue = (customKey, legacyKey) =>
  customAttributes.value[customKey] ??
  legacyAttributes.value[legacyKey] ??
  null;

const parseInvoices = value => {
  if (Array.isArray(value)) return value;
  if (typeof value !== 'string') return [];

  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
};

const invoices = computed(() =>
  parseInvoices(customAttributes.value.sgp_faturas)
    .map(invoice => ({
      id: String(invoice.id || invoice.numero || ''),
      number: String(invoice.numero || invoice.fatura || invoice.id || ''),
      dueDate: invoice.vencimento || null,
      value: invoice.valor ?? null,
      pixAvailable: Boolean(invoice.pix_disponivel),
      barcodeAvailable: Boolean(invoice.codigo_barras_disponivel),
      pdfAvailable: Boolean(invoice.pdf_disponivel),
      paymentLinkAvailable: Boolean(invoice.link_cobranca_disponivel),
    }))
    .filter(invoice => invoice.id)
    .sort((left, right) =>
      String(left.dueDate || '').localeCompare(String(right.dueDate || ''))
    )
);

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
  pixAvailable: Boolean(customAttributes.value.sgp_pix_disponivel),
  barcodeAvailable: Boolean(
    customAttributes.value.sgp_codigo_barras_disponivel
  ),
  pdfAvailable: Boolean(customAttributes.value.sgp_pdf_disponivel),
  paymentLinkAvailable: Boolean(
    customAttributes.value.sgp_link_cobranca_disponivel
  ),
  updatedAt: customAttributes.value.sgp_atualizado_em,
}));

const onuStatusClass = computed(() => {
  const status = String(sgpData.value.onuStatus || '').toLowerCase();
  if (status.includes('online')) return 'text-n-teal-11';
  if (status.includes('offline')) return 'text-n-ruby-11';
  return 'text-n-slate-12';
});

const financialActions = computed(() => [
  {
    key: 'pix',
    action: 'enviar_pix',
    label: t('CONVERSATION.SGP.ACTIONS.PIX'),
    icon: 'i-lucide-qr-code',
    invoiceFlag: 'pixAvailable',
    fallbackFlag: 'pixAvailable',
  },
  {
    key: 'barcode',
    action: 'enviar_barras',
    label: t('CONVERSATION.SGP.ACTIONS.BARCODE'),
    icon: 'i-lucide-scan-line',
    invoiceFlag: 'barcodeAvailable',
    fallbackFlag: 'barcodeAvailable',
  },
  {
    key: 'pdf',
    action: 'enviar_pdf',
    label: t('CONVERSATION.SGP.ACTIONS.PDF'),
    icon: 'i-lucide-file-text',
    invoiceFlag: 'pdfAvailable',
    fallbackFlag: 'pdfAvailable',
  },
  {
    key: 'payment-link',
    action: 'enviar_link_pagamento',
    label: t('CONVERSATION.SGP.ACTIONS.PAYMENT_LINK'),
    icon: 'i-lucide-link',
    invoiceFlag: 'paymentLinkAvailable',
    fallbackFlag: 'paymentLinkAvailable',
  },
]);

const previewInvoices = computed(() => invoices.value.slice(0, 3));
const remainingInvoiceCount = computed(() =>
  Math.max(invoices.value.length - previewInvoices.value.length, 0)
);

const eligibleInvoices = action =>
  invoices.value.filter(invoice => invoice[action.invoiceFlag]);

const isFinancialActionAvailable = action =>
  eligibleInvoices(action).length > 0 || sgpData.value[action.fallbackFlag];

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

const formatDate = value => {
  if (!value) return '-';
  const date = new Date(`${String(value).slice(0, 10)}T00:00:00`);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat('pt-BR').format(date);
};

const formatMoney = value => {
  if (value === null || value === undefined || value === '') return '-';
  const amount = Number(String(value).replace(',', '.'));
  if (Number.isNaN(amount)) return String(value);
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(amount);
};

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
      sgp_action: action,
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

const closePrompts = () => {
  pendingFinancialAction.value = null;
  selectedInvoiceId.value = '';
  showPromiseConfirmation.value = false;
};

const startEditDocument = () => {
  documentValue.value = sgpData.value.cpfCnpj || '';
  isEditingDocument.value = true;
  closePrompts();
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

const consultOnu = () => {
  closePrompts();
  return performAction('consultar_status_onu');
};

const requestFinancialAction = action => {
  const eligible = eligibleInvoices(action);
  closePrompts();

  if (invoices.value.length > 1 && eligible.length) {
    pendingFinancialAction.value = action;
    selectedInvoiceId.value = eligible[0].id;
    return;
  }

  performAction(action.action, {
    ...(eligible[0]?.id && { fatura_id: eligible[0].id }),
  });
};

const confirmFinancialAction = async () => {
  if (!pendingFinancialAction.value || !selectedInvoiceId.value) return;

  const action = pendingFinancialAction.value.action;
  const faturaId = selectedInvoiceId.value;
  closePrompts();
  await performAction(action, { fatura_id: faturaId });
};

const requestPaymentPromise = () => {
  closePrompts();
  showPromiseConfirmation.value = true;
};

const confirmPaymentPromise = async () => {
  closePrompts();
  await performAction('liberar_promessa_2_dias');
};

watch(
  () => props.contact?.id,
  () => {
    isEditingDocument.value = false;
    documentValue.value = '';
    closePrompts();
    setStatus('', '');
  }
);
</script>

<template>
  <section
    class="gt-customer-360 px-4 py-4 border-b border-n-weak bg-n-surface-2"
    data-testid="sgp-panel"
  >
    <div
      class="gt-customer-360__header flex items-start justify-between gap-3 pb-4 border-b border-n-weak/70"
    >
      <div class="min-w-0">
        <h3
          class="flex items-center gap-2.5 text-sm font-semibold tracking-tight text-n-slate-12"
        >
          <span
            class="grid place-items-center size-8 rounded-[10px] bg-n-teal-9/10 border border-n-teal-8/30"
          >
            <span class="i-lucide-user-round-check size-4 text-n-teal-11" />
          </span>
          <span class="min-w-0">
            <span class="block truncate">{{
              t('CONVERSATION.SGP.TITLE')
            }}</span>
            <span class="block mt-0.5 text-[10px] font-normal text-n-slate-10">
              {{ t('CONVERSATION.SGP.SUBTITLE') }}
            </span>
          </span>
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

    <p
      v-if="statusMessage"
      class="sgp-status-message p-2.5 mt-3 text-xs rounded-[10px] border"
      :class="
        statusType === 'success'
          ? 'bg-n-teal-3 text-n-teal-11 border-n-teal-7/30'
          : 'bg-n-ruby-3 text-n-ruby-11 border-n-ruby-7/30'
      "
      role="status"
    >
      {{ statusMessage }}
    </p>

    <div class="sgp-section pt-4">
      <h4
        class="sgp-section-heading mb-2 text-[10px] font-semibold uppercase tracking-[0.14em] text-n-slate-9"
      >
        {{ t('CONVERSATION.SGP.SECTIONS.REGISTRATION') }}
      </h4>
      <div class="sgp-data-block rounded-xl border divide-y divide-n-weak/60">
        <div v-if="sgpData.holderName" class="px-3 py-2.5">
          <p class="text-[10px] uppercase tracking-wide text-n-slate-9">
            {{ t('CONVERSATION.SGP.FIELDS.HOLDER') }}
          </p>
          <p class="mt-0.5 text-sm font-medium text-n-slate-12 truncate">
            {{ sgpData.holderName }}
          </p>
        </div>
        <div class="flex items-center justify-between gap-3 px-3 py-2.5">
          <div class="flex-1 min-w-0">
            <p class="text-[10px] uppercase tracking-wide text-n-slate-9">
              {{ t('CONVERSATION.SGP.FIELDS.DOCUMENT') }}
            </p>
            <p
              v-if="!isEditingDocument"
              class="mt-0.5 text-sm font-medium text-n-slate-12 truncate"
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
              class="w-full px-2.5 py-1.5 mt-1 text-sm outline-none rounded-lg bg-n-background border border-n-strong focus:border-n-blue-9"
              :placeholder="t('CONVERSATION.SGP.DOCUMENT_PLACEHOLDER')"
              :disabled="isLoading"
              data-testid="sgp-document-input"
            />
          </div>
          <button
            v-if="!isEditingDocument"
            class="px-2 py-1 text-xs font-medium rounded-lg text-n-blue-11 hover:bg-n-blue-3/60"
            :disabled="isLoading"
            @click="startEditDocument"
          >
            {{ t('CONVERSATION.SGP.CHANGE') }}
          </button>
          <div v-else class="flex items-center gap-2">
            <button
              class="px-2.5 py-1.5 text-xs font-medium rounded-lg bg-n-teal-3 text-n-teal-11 disabled:opacity-50"
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
      </div>
    </div>

    <div class="sgp-section pt-4">
      <h4
        class="sgp-section-heading mb-2 text-[10px] font-semibold uppercase tracking-[0.14em] text-n-slate-9"
      >
        {{ t('CONVERSATION.SGP.SECTIONS.CONNECTION') }}
      </h4>
      <div class="sgp-data-block rounded-xl border divide-y divide-n-weak/60">
        <div class="grid grid-cols-2 gap-3 px-3 py-2.5">
          <div class="min-w-0">
            <p class="text-[10px] uppercase tracking-wide text-n-slate-9">
              {{ t('CONVERSATION.SGP.FIELDS.CONTRACT') }}
            </p>
            <p class="mt-0.5 text-sm font-medium text-n-slate-12 truncate">
              {{
                sgpData.contract ||
                sgpData.contractStatus ||
                t('CONVERSATION.SGP.NOT_INFORMED')
              }}
            </p>
            <p
              v-if="sgpData.contract && sgpData.contractStatus"
              class="text-[10px] text-n-slate-10 truncate"
            >
              {{ sgpData.contractStatus }}
            </p>
          </div>
          <div class="min-w-0">
            <p class="text-[10px] uppercase tracking-wide text-n-slate-9">
              {{ t('CONVERSATION.SGP.FIELDS.PLAN') }}
            </p>
            <p class="mt-0.5 text-sm font-medium text-n-slate-12 truncate">
              {{ sgpData.plan || t('CONVERSATION.SGP.NOT_INFORMED') }}
            </p>
          </div>
        </div>
        <div class="flex items-center justify-between gap-3 px-3 py-2.5">
          <div class="min-w-0">
            <p class="text-[10px] uppercase tracking-wide text-n-slate-9">
              {{ t('CONVERSATION.SGP.FIELDS.ONU') }}
            </p>
            <p
              class="mt-0.5 text-sm font-medium truncate"
              :class="onuStatusClass"
            >
              {{
                sgpData.onuStatus ||
                sgpData.onu ||
                t('CONVERSATION.SGP.NOT_INFORMED')
              }}
            </p>
            <p
              v-if="sgpData.onu && sgpData.onuStatus"
              class="text-[10px] text-n-slate-10 truncate"
            >
              {{ sgpData.onu }}
            </p>
          </div>
          <button
            class="sgp-action-button px-2.5 py-1.5 rounded-lg text-[11px] font-semibold border border-n-weak bg-n-surface-2 text-n-slate-12 hover:bg-n-blue-3/50 hover:border-n-blue-8/40 disabled:opacity-50 transition-colors duration-150"
            :disabled="isLoading || !sgpData.cpfCnpj"
            @click="consultOnu"
          >
            <span
              class="size-3.5 inline-block align-text-bottom mr-1"
              :class="
                activeAction === 'consultar_status_onu'
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-radio-tower'
              "
            />
            {{ t('CONVERSATION.SGP.ACTIONS.ONU') }}
          </button>
        </div>
      </div>
    </div>

    <div class="sgp-section pt-4">
      <h4
        class="sgp-section-heading mb-2 text-[10px] font-semibold uppercase tracking-[0.14em] text-n-slate-9"
      >
        {{ t('CONVERSATION.SGP.SECTIONS.FINANCIAL') }}
      </h4>
      <div class="sgp-data-block rounded-xl border px-3 py-2.5">
        <div v-if="previewInvoices.length" class="space-y-1.5">
          <div
            v-for="invoice in previewInvoices"
            :key="invoice.id"
            class="flex items-center justify-between gap-2 text-[11px]"
          >
            <span class="text-n-slate-10">{{
              formatDate(invoice.dueDate)
            }}</span>
            <span class="font-medium text-n-slate-12">{{
              formatMoney(invoice.value)
            }}</span>
          </div>
          <p v-if="remainingInvoiceCount" class="text-[10px] text-n-slate-9">
            {{
              t('CONVERSATION.SGP.MORE_INVOICES', {
                count: remainingInvoiceCount,
              })
            }}
          </p>
        </div>
        <div v-else class="flex items-center justify-between gap-2">
          <span class="text-[11px] text-n-slate-10">
            {{
              sgpData.invoiceDueDate ||
              sgpData.invoiceStatus ||
              t('CONVERSATION.SGP.NOT_INFORMED')
            }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ sgpData.invoiceValue || t('CONVERSATION.SGP.NOT_INFORMED') }}
          </span>
        </div>
      </div>
    </div>

    <div
      v-if="pendingFinancialAction"
      class="p-3 mt-3 rounded-xl border border-n-strong bg-n-alpha-2"
      data-testid="sgp-invoice-selector"
    >
      <p class="text-xs font-semibold text-n-slate-12">
        {{ t('CONVERSATION.SGP.SELECT_INVOICE') }}
      </p>
      <div class="mt-2 space-y-1.5">
        <label
          v-for="invoice in eligibleInvoices(pendingFinancialAction)"
          :key="invoice.id"
          class="flex items-center gap-2 p-2 rounded-lg cursor-pointer bg-n-alpha-1 hover:bg-n-alpha-2"
        >
          <input
            v-model="selectedInvoiceId"
            type="radio"
            :value="invoice.id"
            class="accent-n-blue-9"
          />
          <span class="flex-1 text-[11px] text-n-slate-11">
            {{
              t('CONVERSATION.SGP.INVOICE_SUMMARY', {
                date: formatDate(invoice.dueDate),
                value: formatMoney(invoice.value),
              })
            }}
          </span>
          <span class="text-[10px] text-n-slate-9">
            {{
              t('CONVERSATION.SGP.INVOICE_NUMBER', {
                number: invoice.number,
              })
            }}
          </span>
        </label>
      </div>
      <div class="flex justify-end gap-2 mt-2">
        <button
          class="text-xs text-n-slate-10 hover:text-n-slate-12"
          @click="closePrompts"
        >
          {{ t('CONVERSATION.SGP.CANCEL') }}
        </button>
        <button
          class="px-2.5 py-1 text-xs font-medium rounded-lg bg-n-blue-9 text-white"
          @click="confirmFinancialAction"
        >
          {{ t('CONVERSATION.SGP.SEND') }}
        </button>
      </div>
    </div>

    <div
      v-if="showPromiseConfirmation"
      class="p-3 mt-3 rounded-xl border border-n-strong bg-n-alpha-2"
      data-testid="sgp-promise-confirmation"
    >
      <p class="text-xs font-semibold text-n-slate-12">
        {{ t('CONVERSATION.SGP.PROMISE_CONFIRMATION') }}
      </p>
      <p class="mt-1 text-[11px] text-n-slate-10">
        {{ t('CONVERSATION.SGP.PROMISE_HELP') }}
      </p>
      <div class="flex justify-end gap-2 mt-2">
        <button
          class="text-xs text-n-slate-10 hover:text-n-slate-12"
          @click="closePrompts"
        >
          {{ t('CONVERSATION.SGP.CANCEL') }}
        </button>
        <button
          class="px-2.5 py-1 text-xs font-medium rounded-lg bg-n-blue-9 text-white"
          @click="confirmPaymentPromise"
        >
          {{ t('CONVERSATION.SGP.CONFIRM') }}
        </button>
      </div>
    </div>

    <div class="sgp-section pt-4">
      <h4
        class="sgp-section-heading mb-2 text-[10px] font-semibold uppercase tracking-[0.14em] text-n-slate-9"
      >
        {{ t('CONVERSATION.SGP.SECTIONS.ACTIONS') }}
      </h4>
      <div class="grid grid-cols-2 gap-2">
        <button
          v-for="action in financialActions"
          :key="action.key"
          class="sgp-action-button py-2.5 px-2 rounded-[10px] text-[11px] font-semibold border border-n-weak bg-n-surface-2 text-n-slate-12 hover:bg-n-blue-3/50 hover:border-n-blue-8/40 disabled:opacity-40 disabled:cursor-not-allowed transition-colors duration-150"
          :disabled="
            isLoading || !sgpData.cpfCnpj || !isFinancialActionAvailable(action)
          "
          :data-testid="`sgp-action-${action.key}`"
          @click="requestFinancialAction(action)"
        >
          <span
            class="size-3.5 inline-block align-text-bottom mr-1"
            :class="
              activeAction === action.action
                ? 'i-lucide-loader-circle animate-spin'
                : action.icon
            "
          />
          {{ action.label }}
        </button>
        <button
          class="sgp-action-button col-span-2 py-2.5 px-2 rounded-[10px] text-[11px] font-semibold border border-n-weak bg-n-surface-2 text-n-slate-12 hover:bg-n-amber-3/40 hover:border-n-amber-8/35 disabled:opacity-50 transition-colors duration-150"
          :disabled="isLoading || !sgpData.cpfCnpj"
          data-testid="sgp-action-payment-promise"
          @click="requestPaymentPromise"
        >
          <span
            class="size-3.5 inline-block align-text-bottom mr-1"
            :class="
              activeAction === 'liberar_promessa_2_dias'
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-calendar-clock'
            "
          />
          {{ t('CONVERSATION.SGP.ACTIONS.PAYMENT_PROMISE') }}
        </button>
      </div>
    </div>
  </section>
</template>
