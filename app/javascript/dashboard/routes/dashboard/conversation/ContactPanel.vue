<script setup>
import { computed, watch, onMounted, ref } from 'vue';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import ContactConversations from './ContactConversations.vue';
import ConversationAction from './ConversationAction.vue';
import ContactInfo from './contact/ContactInfo.vue';
import ContactNotes from './contact/ContactNotes.vue';
import ConversationInfo from './ConversationInfo.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';
import Draggable from 'vuedraggable';
import MacrosList from './Macros/List.vue';
import ShopifyOrdersList from 'dashboard/components/widgets/conversation/ShopifyOrdersList.vue';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import LinearIssuesList from 'dashboard/components/widgets/conversation/linear/IssuesList.vue';
import LinearSetupCTA from 'dashboard/components/widgets/conversation/linear/LinearSetupCTA.vue';

import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const {
  updateUISettings,
  isContactSidebarItemOpen,
  conversationSidebarItemsOrder,
  toggleSidebarUIState,
} = useUISettings();

const dragging = ref(false);
const conversationSidebarItems = ref([]);

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);

const isShopifyFeatureEnabled = computed(
  () => shopifyIntegration.value.enabled
);

const { isCloudFeatureEnabled } = useAccount();

const isLinearFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR)
);

const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isLinearClientIdConfigured = computed(() => {
  return !!linearIntegration.value?.id;
});

const isLinearConnected = computed(
  () => linearIntegration.value?.enabled || false
);

const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const conversationId = computed(() => props.conversationId);
const conversationMetadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const currentConversationMetaData = computed(() =>
  conversationMetadataGetter.value(conversationId.value)
);
const conversationAdditionalAttributes = computed(
  () => currentConversationMetaData.value.additional_attributes || {}
);

const channelType = computed(() => currentChat.value.meta?.channel);

const contactGetter = useMapGetter('contacts/getContact');
const contactId = computed(() => currentChat.value.meta?.sender?.id);
const contact = computed(() => contactGetter.value(contactId.value));
const contactAdditionalAttributes = computed(
  () => contact.value.additional_attributes || {}
);

const getContactDetails = () => {
  if (contactId.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

const onDragEnd = () => {
  dragging.value = false;
  updateUISettings({
    conversation_sidebar_items_order: conversationSidebarItems.value,
  });
};

const closeContactPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};

onMounted(() => {
  conversationSidebarItems.value = conversationSidebarItemsOrder.value;
  getContactDetails();
  store.dispatch('attributes/get', 0);
  // Load integrations to ensure linear integration state is available
  store.dispatch('integrations/get', 'linear');
});

const { addLabelToConversation } = useConversationLabels();

const triggerSgpAction = async (label) => {
  try {
    await addLabelToConversation({ title: label });
    useAlert(`Ação solicitada. O n8n processará o comando: ${label}`);
  } catch (error) {
    useAlert(`Erro ao enviar comando ${label}.`);
  }
};

const isEditingCpf = ref(false);
const editCpfValue = ref('');

const startEditCpf = () => {
  editCpfValue.value = contactAdditionalAttributes.value.cpf || '';
  isEditingCpf.value = true;
};

const saveCpf = async () => {
  try {
    await store.dispatch('contacts/update', {
      id: contactId.value,
      custom_attributes: {
        ...contactAdditionalAttributes.value,
        cpf: editCpfValue.value
      }
    });
    isEditingCpf.value = false;
    useAlert('CPF atualizado com sucesso.');
  } catch (error) {
    useAlert('Erro ao atualizar CPF.');
  }
};
</script>

<template>
  <div class="w-full">
    <SidebarActionsHeader
      :title="$t('CONVERSATION.SIDEBAR.CONTACT')"
      @close="closeContactPanel"
    />
    <ContactInfo :contact="contact" :channel-type="channelType" />
    
    <!-- SGP Panel -->
    <div class="px-4 py-4 border-b border-n-weak">
      <h3 class="text-sm font-semibold text-n-slate-12 mb-3">SGP - Grupo Telecom</h3>
      
      <!-- Custom Attributes Cards -->
      <div class="grid grid-cols-2 gap-2 mb-4">
        <div class="bg-n-surface-2 p-2 rounded-md border border-n-weak shadow-sm">
          <p class="text-xs text-n-slate-10 mb-1">Status Contrato</p>
          <p class="text-sm font-medium" :class="{'text-green-600': contactAdditionalAttributes.status_contrato === 'Ativo', 'text-red-600': contactAdditionalAttributes.status_contrato === 'Bloqueado'}">{{ contactAdditionalAttributes.status_contrato || 'N/A' }}</p>
        </div>
        <div class="bg-n-surface-2 p-2 rounded-md border border-n-weak shadow-sm">
          <p class="text-xs text-n-slate-10 mb-1">Status ONU</p>
          <p class="text-sm font-medium" :class="{'text-green-600': contactAdditionalAttributes.status_onu === 'Online', 'text-red-600': contactAdditionalAttributes.status_onu === 'Offline'}">{{ contactAdditionalAttributes.status_onu || 'N/A' }}</p>
        </div>
        <div class="bg-n-surface-2 p-2 rounded-md border border-n-weak shadow-sm">
          <p class="text-xs text-n-slate-10 mb-1">Plano SGP</p>
          <p class="text-sm font-medium truncate" :title="contactAdditionalAttributes.plano_sgp">{{ contactAdditionalAttributes.plano_sgp || 'N/A' }}</p>
        </div>
        <div class="bg-n-surface-2 p-2 rounded-md border border-n-weak shadow-sm">
          <p class="text-xs text-n-slate-10 mb-1">Fatura / Venc</p>
          <p class="text-sm font-medium truncate" :title="contactAdditionalAttributes.valor_fatura + ' - ' + contactAdditionalAttributes.vencimento_fatura">
            {{ contactAdditionalAttributes.valor_fatura || 'N/A' }} - {{ contactAdditionalAttributes.vencimento_fatura || 'N/A' }}
          </p>
        </div>
      </div>

      <!-- CPF inline edit -->
      <div class="flex items-center justify-between mb-4 bg-n-surface-2 p-2 rounded-md border border-n-weak shadow-sm">
        <div class="flex-1 mr-2">
          <p class="text-xs text-n-slate-10 mb-0.5">CPF do Cliente</p>
          <p class="text-sm font-medium" v-if="!isEditingCpf">{{ contactAdditionalAttributes.cpf || 'Não informado' }}</p>
          <input v-else v-model="editCpfValue" type="text" class="w-full text-sm bg-n-background border border-n-strong rounded px-2 py-1 outline-none focus:border-n-brand" placeholder="000.000.000-00" />
        </div>
        <button v-if="!isEditingCpf" @click="startEditCpf" class="text-xs text-n-brand font-medium hover:underline">Alterar</button>
        <div v-else class="flex gap-2 items-center">
          <button @click="saveCpf" class="text-xs bg-green-100 text-green-700 px-2 py-1 rounded font-medium hover:bg-green-200">Salvar</button>
          <button @click="isEditingCpf = false" class="text-xs text-n-slate-10 hover:text-n-slate-12">Cancelar</button>
        </div>
      </div>

      <!-- Action Buttons -->
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
        <button @click="triggerSgpAction('cmd_reiniciar_onu')" class="bg-n-surface-2 hover:bg-n-surface-3 text-n-slate-12 text-xs font-medium py-2 px-1 rounded border border-n-weak transition-colors text-center truncate">Reiniciar ONU</button>
        <button @click="triggerSgpAction('cmd_gerar_pix')" class="bg-n-surface-2 hover:bg-n-surface-3 text-n-slate-12 text-xs font-medium py-2 px-1 rounded border border-n-weak transition-colors text-center truncate">Cód Pix</button>
        <button @click="triggerSgpAction('cmd_codigo_barras')" class="bg-n-surface-2 hover:bg-n-surface-3 text-n-slate-12 text-xs font-medium py-2 px-1 rounded border border-n-weak transition-colors text-center truncate">Cód Barras</button>
        <button @click="triggerSgpAction('cmd_pdf_fatura')" class="bg-n-surface-2 hover:bg-n-surface-3 text-n-slate-12 text-xs font-medium py-2 px-1 rounded border border-n-weak transition-colors text-center truncate">PDF Fatura</button>
        <button @click="triggerSgpAction('cmd_promessa_pgto')" class="bg-n-surface-2 hover:bg-n-surface-3 text-n-slate-12 text-xs font-medium py-2 px-1 rounded border border-n-weak transition-colors text-center truncate col-span-2 sm:col-span-1">Promessa Pgto</button>
      </div>
    </div>

    <div class="px-2 pb-8 list-group">
      <Draggable
        :list="conversationSidebarItems"
        animation="200"
        ghost-class="ghost"
        handle=".drag-handle"
        item-key="name"
        class="flex flex-col gap-3"
        @start="dragging = true"
        @end="onDragEnd"
      >
        <template #item="{ element }">
          <div
            v-if="element.name === 'conversation_actions'"
            class="conversation--actions"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS')"
              :is-open="isContactSidebarItemOpen('is_conv_actions_open')"
              @toggle="
                value => toggleSidebarUIState('is_conv_actions_open', value)
              "
            >
              <ConversationAction
                :conversation-id="conversationId"
                :inbox-id="inboxId"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'conversation_info'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO')"
              :is-open="isContactSidebarItemOpen('is_conv_details_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_conv_details_open', value)
              "
            >
              <ConversationInfo
                :conversation-attributes="conversationAdditionalAttributes"
                :contact-attributes="contactAdditionalAttributes"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'contact_attributes'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES')"
              :is-open="isContactSidebarItemOpen('is_contact_attributes_open')"
              compact
              @toggle="
                value =>
                  toggleSidebarUIState('is_contact_attributes_open', value)
              "
            >
              <CustomAttributes
                attribute-type="contact_attribute"
                attribute-from="conversation_contact_panel"
                :contact-id="contact.id"
                :empty-state-message="
                  $t('CONVERSATION_CUSTOM_ATTRIBUTES.NO_RECORDS_FOUND')
                "
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'previous_conversation'">
            <AccordionItem
              v-if="contact.id"
              :title="
                $t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION')
              "
              :is-open="isContactSidebarItemOpen('is_previous_conv_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_previous_conv_open', value)
              "
            >
              <ContactConversations
                :contact-id="contact.id"
                :conversation-id="conversationId"
              />
            </AccordionItem>
          </div>
          <woot-feature-toggle
            v-else-if="element.name === 'macros'"
            feature-key="macros"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MACROS')"
              :is-open="isContactSidebarItemOpen('is_macro_open')"
              compact
              @toggle="value => toggleSidebarUIState('is_macro_open', value)"
            >
              <MacrosList :conversation-id="conversationId" />
            </AccordionItem>
          </woot-feature-toggle>
          <div
            v-else-if="
              element.name === 'linear_issues' &&
              isLinearFeatureEnabled &&
              isLinearClientIdConfigured
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.LINEAR_ISSUES')"
              :is-open="isContactSidebarItemOpen('is_linear_issues_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_linear_issues_open', value)
              "
            >
              <LinearSetupCTA v-if="!isLinearConnected" />
              <LinearIssuesList v-else :conversation-id="conversationId" />
            </AccordionItem>
          </div>
          <div
            v-else-if="
              element.name === 'shopify_orders' && isShopifyFeatureEnabled
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHOPIFY_ORDERS')"
              :is-open="isContactSidebarItemOpen('is_shopify_orders_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_shopify_orders_open', value)
              "
            >
              <ShopifyOrdersList :contact-id="contactId" />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'contact_notes'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES')"
              :is-open="isContactSidebarItemOpen('is_contact_notes_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_contact_notes_open', value)
              "
            >
              <ContactNotes :contact-id="contactId" />
            </AccordionItem>
          </div>
        </template>
      </Draggable>
    </div>
  </div>
</template>

<style lang="scss" scoped>
::v-deep {
  .contact--profile {
    @apply pb-3 border-b border-solid border-n-weak;
  }
}
</style>
