<script setup>
import {
  ref,
  unref,
  provide,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import {
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store.js';

import ChatListHeader from './ChatListHeader.vue';
import ConversationList from './ConversationList.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConversationFilter from 'next/filter/ConversationFilter.vue';
import SaveCustomView from 'next/filter/SaveCustomView.vue';
import ChatTypeTabs from './widgets/ChatTypeTabs.vue';
import DeleteCustomViews from 'dashboard/routes/dashboard/customviews/DeleteCustomViews.vue';
import ConversationBulkActions from './widgets/conversation/conversationBulkActions/Index.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions';
import { useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';
import { useEmitter } from 'dashboard/composables/emitter';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useFilter } from 'shared/composables/useFilter';

import { emitter } from 'shared/helpers/mitt';

import wootConstants from 'dashboard/constants/globals';
import advancedFilterOptions from './widgets/conversation/advancedFilterItems';
import filterQueryGenerator from '../helper/filterQueryGenerator.js';
import languages from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import countries from 'shared/constants/countries';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import { conversationListPageURL } from '../helper/URLHelper';
import {
  isOnMentionsView,
  isOnParticipatingView,
  isOnUnattendedView,
} from '../store/modules/conversations/helpers/actionHelpers';
import { matchesFilters } from '../store/modules/conversations/helpers/filterHelpers';
import { CONVERSATION_EVENTS } from '../helper/AnalyticsHelper/events';
import ConversationApi from 'dashboard/api/inbox/conversation';
import {
  buildConversationFilterQuery,
  normalizeAssigneeView,
  normalizeConversationStatus,
} from 'dashboard/helper/conversationFilterQueryHelper';
import {
  createConversationStatsRefresher,
  loadConversationStats,
} from 'dashboard/helper/conversationStatsRefresh';

const props = defineProps({
  conversationInbox: { type: [String, Number], default: 0 },
  teamId: { type: [String, Number], default: 0 },
  label: { type: String, default: '' },
  conversationType: { type: String, default: '' },
  foldersId: { type: [String, Number], default: 0 },
  showConversationList: { default: true, type: Boolean },
  isOnExpandedLayout: { default: false, type: Boolean },
});

const emit = defineEmits(['conversationLoad']);
const { uiSettings } = useUISettings();
const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useStore();
const { isFeatureFlagEnabled } = usePolicy();

const resolveAttributesModalRef = ref(null);

const initialStatus =
  normalizeConversationStatus(route.query.status) ||
  wootConstants.STATUS_TYPE.OPEN;
const activeAssigneeTab = ref(
  normalizeAssigneeView(
    route.query.view,
    initialStatus === wootConstants.STATUS_TYPE.RESOLVED
      ? wootConstants.ASSIGNEE_TYPE.ALL
      : wootConstants.ASSIGNEE_TYPE.ME
  )
);
const activeStatus = ref(initialStatus);
const activeSortBy = ref(wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC);
const showAdvancedFilters = ref(false);
// chatsOnView is to store the chats that are currently visible on the screen,
// which mirrors the conversationList.
const chatsOnView = ref([]);
const foldersQuery = ref({});
const showAddFoldersModal = ref(false);
const showDeleteFoldersModal = ref(false);
const appliedFilter = ref([]);
const botTabCounts = ref({
  total: 0,
  unassigned: 0,
});
const tabStatsError = ref(false);
let tabStatsRequestSequence = 0;
const advancedFilterTypes = ref(
  advancedFilterOptions.map(filter => ({
    ...filter,
    attributeName: t(`FILTER.ATTRIBUTES.${filter.attributeI18nKey}`),
  }))
);

const currentUser = useMapGetter('getCurrentUser');
const chatLists = useMapGetter('getFilteredConversations');
const mineChatsList = useMapGetter('getMineChats');
const allChatList = useMapGetter('getAllStatusChats');
const unAssignedChatsList = useMapGetter('getUnAssignedChats');
const participatingChatsList = useMapGetter('getParticipatingChats');
const chatListLoading = useMapGetter('getChatListLoadingStatus');
const chatListRequestError = useMapGetter('getChatListRequestError');
const activeInbox = useMapGetter('getSelectedInbox');
const conversationStats = useMapGetter('conversationStats/getStats');
const appliedFilters = useMapGetter('getAppliedConversationFiltersV2');
const folders = useMapGetter('customViews/getConversationCustomViews');
const agentList = useMapGetter('agents/getAgents');
const teamsList = useMapGetter('teams/getTeams');
const inboxesList = useMapGetter('inboxes/getInboxes');
const campaigns = useMapGetter('campaigns/getAllCampaigns');
const labels = useMapGetter('labels/getLabels');
// We can't useFunctionGetter here since it needs to be called on setup?
const getTeamFn = useMapGetter('teams/getTeam');
const getConversationById = useMapGetter('getConversationById');

const {
  selectedConversations,
  selectedInboxes,
  selectConversation,
  deSelectConversation,
  selectAllConversations,
  resetBulkActions,
  isConversationSelected,
  onAssignAgent,
  onAssignLabels,
  onRemoveLabels,
  onAssignTeamsForBulk,
  onUpdateConversations,
} = useBulkActions();

const {
  initializeStatusAndAssigneeFilterToModal,
  initializeInboxTeamAndLabelFilterToModal,
} = useFilter({
  filteri18nKey: 'FILTER',
  attributeModel: 'conversation_attribute',
});

const { checkMissingAttributes } = useConversationRequiredAttributes();

// computed

const hasAppliedFilters = computed(() => {
  return appliedFilters.value.length !== 0;
});

const canonicalBucketsEnabled = computed(() =>
  isFeatureFlagEnabled(FEATURE_FLAGS.CONVERSATION_OPERATIONAL_BUCKETS)
);

const activeFolder = computed(() => {
  if (props.foldersId) {
    const activeView = folders.value.filter(
      view => view.id === Number(props.foldersId)
    );
    const [firstValue] = activeView;
    return firstValue;
  }
  return undefined;
});

const activeFolderName = computed(() => {
  return activeFolder.value?.name;
});

const hasActiveFolders = computed(() => {
  return Boolean(activeFolder.value && props.foldersId !== 0);
});

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return hasAppliedFilters.value || hasActiveFolders.value;
});

const currentUserDetails = computed(() => {
  const { id, name } = currentUser.value;
  return { id, name };
});

const unassignedTabCount = computed(() => {
  if (canonicalBucketsEnabled.value) {
    return botTabCounts.value.humanQueue || 0;
  }
  const rawUnassignedCount = conversationStats.value.unAssignedCount || 0;
  return Math.max(rawUnassignedCount - botTabCounts.value.unassigned, 0);
});

const botChatsCount = computed(() => botTabCounts.value.total || 0);

const assigneeTabItems = computed(() => [
  {
    key: 'me',
    name: t('CHAT_LIST.ASSIGNEE_TYPE_TABS.me'),
    count: canonicalBucketsEnabled.value
      ? botTabCounts.value.mine || 0
      : conversationStats.value.mineCount || 0,
  },
  {
    key: 'unassigned',
    name: t('CHAT_LIST.ASSIGNEE_TYPE_TABS.unassigned'),
    count: unassignedTabCount.value,
  },
  {
    key: 'bot',
    name: t('CHAT_LIST.ASSIGNEE_TYPE_TABS.all'),
    count: botChatsCount.value,
  },
]);

const showAssigneeInConversationCard = computed(() => {
  return (
    hasAppliedFiltersOrActiveFolders.value ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL
  );
});

// Map the frontend-only 'bot' tab key to 'all' for pagination store reads,
// because the API request uses assigneeType='all' when fetching bot conversations.
const storePaginationKey = computed(() => {
  if (activeAssigneeTab.value === 'bot') return 'all';
  return activeAssigneeTab.value;
});

const currentPageFilterKey = computed(() => {
  return hasAppliedFiltersOrActiveFolders.value
    ? 'appliedFilters'
    : storePaginationKey.value;
});

const inbox = useFunctionGetter('inboxes/getInbox', activeInbox);
const currentPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  storePaginationKey
);
const currentFiltersPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  currentPageFilterKey
);
const hasCurrentPageEndReached = useFunctionGetter(
  'conversationPage/getHasEndReached',
  currentPageFilterKey
);

const conversationCustomAttributes = useFunctionGetter(
  'attributes/getAttributesByModel',
  'conversation_attribute'
);

const activeAssigneeTabCount = computed(() => {
  if (activeAssigneeTab.value === 'unassigned') {
    return unassignedTabCount.value;
  }
  if (activeAssigneeTab.value === 'bot') {
    return botChatsCount.value;
  }
  if (activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL) {
    return conversationStats.value.allCount || 0;
  }
  return conversationStats.value.mineCount || 0;
});

const conversationListPagination = computed(() => {
  const conversationsPerPage = 25;
  const hasChatsOnView =
    chatsOnView.value &&
    Array.isArray(chatsOnView.value) &&
    !chatsOnView.value.length;
  const isNoFiltersOrFoldersAndChatListNotEmpty =
    !hasAppliedFiltersOrActiveFolders.value && hasChatsOnView;
  const isUnderPerPage =
    chatsOnView.value.length < conversationsPerPage &&
    activeAssigneeTabCount.value < conversationsPerPage &&
    activeAssigneeTabCount.value > chatsOnView.value.length;

  if (isNoFiltersOrFoldersAndChatListNotEmpty && isUnderPerPage) {
    return 1;
  }

  return currentPage.value + 1;
});

const conversationFilters = computed(() => {
  let filterLabels;
  if (activeAssigneeTab.value === 'bot') {
    filterLabels = ['bot-bia'];
  } else if (props.label) {
    filterLabels = [props.label];
  }

  return {
    inboxId: props.conversationInbox ? props.conversationInbox : undefined,
    assigneeType:
      activeAssigneeTab.value === 'bot' ? 'all' : activeAssigneeTab.value,
    status: activeStatus.value,
    sortBy: activeSortBy.value,
    page: conversationListPagination.value,
    labels: filterLabels,
    teamId: props.teamId || undefined,
    conversationType: props.conversationType || undefined,
    operationalBucket: canonicalBucketsEnabled.value
      ? {
          me: 'mine',
          unassigned: 'human_queue',
          bot: 'bia',
        }[activeAssigneeTab.value]
      : undefined,
  };
});

const activeTeam = computed(() => {
  if (props.teamId) {
    return getTeamFn.value(props.teamId);
  }
  return {};
});

const pageTitle = computed(() => {
  if (hasAppliedFilters.value) {
    return t('CHAT_LIST.TAB_HEADING');
  }
  if (inbox.value.name) {
    return inbox.value.name;
  }
  if (activeTeam.value.name) {
    return activeTeam.value.name;
  }
  if (props.label) {
    return `#${props.label}`;
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.MENTION) {
    return t('CHAT_LIST.MENTION_HEADING');
  }
  if (
    props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
  ) {
    return t('CONVERSATION_PARTICIPANTS.SIDEBAR_MENU_TITLE');
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.UNATTENDED) {
    return t('CHAT_LIST.UNATTENDED_HEADING');
  }
  if (hasActiveFolders.value) {
    return activeFolder.value.name;
  }
  return t('CHAT_LIST.TAB_HEADING');
});

function filterByAssigneeTab(conversations) {
  if (canonicalBucketsEnabled.value) {
    const expectedBucket = {
      me: 'mine',
      unassigned: 'human_queue',
      bot: 'bia',
    }[activeAssigneeTab.value];
    return conversations.filter(
      conversation => conversation.operational_bucket === expectedBucket
    );
  }

  if (activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ME) {
    return conversations.filter(
      c => c.meta?.assignee?.id === currentUser.value?.id
    );
  }
  if (activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.UNASSIGNED) {
    return conversations.filter(c => !c.meta?.assignee);
  }
  return [...conversations];
}

const conversationList = computed(() => {
  let localConversationList = [];

  if (!hasAppliedFiltersOrActiveFolders.value) {
    const filters = conversationFilters.value;
    if (
      props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
    ) {
      localConversationList = filterByAssigneeTab(
        participatingChatsList.value(filters)
      );
    } else if (activeAssigneeTab.value === 'me') {
      localConversationList = filterByAssigneeTab(mineChatsList.value(filters));
    } else if (activeAssigneeTab.value === 'unassigned') {
      localConversationList = filterByAssigneeTab(
        unAssignedChatsList.value(filters)
      );
    } else if (activeAssigneeTab.value === 'bot') {
      // Keep tab-scoped filtering to prevent realtime bleed from other tabs.
      localConversationList = filterByAssigneeTab(allChatList.value(filters));
    } else {
      localConversationList = [...allChatList.value(filters)];
    }
  } else {
    localConversationList = [...chatLists.value];
  }

  if (activeFolder.value) {
    const { payload } = activeFolder.value.query;
    localConversationList = localConversationList.filter(conversation => {
      return matchesFilters(conversation, payload);
    });
  }

  return localConversationList;
});

const showEndOfListMessage = computed(() => {
  return !!(
    conversationList.value.length &&
    hasCurrentPageEndReached.value &&
    !chatListLoading.value
  );
});

const allConversationsSelected = computed(() => {
  return (
    conversationList.value.length === selectedConversations.value.length &&
    conversationList.value.every(el =>
      selectedConversations.value.includes(el.id)
    )
  );
});

const uniqueInboxes = computed(() => {
  return [...new Set(selectedInboxes.value)];
});

// ---------------------- Methods -----------------------
function setFiltersFromUISettings() {
  const { conversations_filter_by: filterBy = {} } = uiSettings.value;
  const { status, order_by: orderBy } = filterBy;
  const nextStatus =
    normalizeConversationStatus(route.query.status) ||
    normalizeConversationStatus(status) ||
    wootConstants.STATUS_TYPE.OPEN;
  activeStatus.value = nextStatus;
  if (nextStatus === wootConstants.STATUS_TYPE.RESOLVED && !route.query.view) {
    activeAssigneeTab.value = wootConstants.ASSIGNEE_TYPE.ALL;
  } else if (
    nextStatus !== wootConstants.STATUS_TYPE.RESOLVED &&
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL
  ) {
    activeAssigneeTab.value = wootConstants.ASSIGNEE_TYPE.ME;
  }
  activeSortBy.value = Object.values(wootConstants.SORT_BY_TYPE).includes(
    orderBy
  )
    ? orderBy
    : wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC;
}

function emitConversationLoaded() {
  emit('conversationLoad');
}

const isViewingResolved = computed(
  () => activeStatus.value === wootConstants.STATUS_TYPE.RESOLVED
);

function toggleResolvedView() {
  if (isViewingResolved.value) {
    activeStatus.value = wootConstants.STATUS_TYPE.OPEN;
    activeAssigneeTab.value = wootConstants.ASSIGNEE_TYPE.ME;
  } else {
    activeStatus.value = wootConstants.STATUS_TYPE.RESOLVED;
    // When entering resolved view, reset to 'all' so we don't filter by assignee
    activeAssigneeTab.value = wootConstants.ASSIGNEE_TYPE.ALL;
  }
  // Function declarations are hoisted; keeping handlers near their UI state
  // makes this large component easier to scan.
  // eslint-disable-next-line no-use-before-define
  redirectToConversationList(activeAssigneeTab.value, activeStatus.value);
  // eslint-disable-next-line no-use-before-define
  resetAndFetchData();
}

function fetchFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: filterQueryGenerator(payload),
      page,
    })
    .then(emitConversationLoaded);

  showAdvancedFilters.value = false;
}

function fetchSavedFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: payload,
      page,
    })
    .then(emitConversationLoaded);
}

function onApplyFilter(payload) {
  payload = useSnakeCase(payload);
  resetBulkActions();
  foldersQuery.value = filterQueryGenerator(payload);
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  fetchFilteredConversations(payload);
}

function closeAdvanceFiltersModal() {
  showAdvancedFilters.value = false;
  appliedFilter.value = [];
}

function onUpdateSavedFilter(payload, folderName) {
  const transformedPayload = useSnakeCase(payload);
  const payloadData = {
    ...unref(activeFolder),
    name: unref(folderName),
    query: filterQueryGenerator(transformedPayload),
  };
  store.dispatch('customViews/update', payloadData);
  closeAdvanceFiltersModal();
}

function onClickOpenAddFoldersModal() {
  showAddFoldersModal.value = true;
}

function onCloseAddFoldersModal() {
  showAddFoldersModal.value = false;
}

function onClickOpenDeleteFoldersModal() {
  showDeleteFoldersModal.value = true;
}

function onCloseDeleteFoldersModal() {
  showDeleteFoldersModal.value = false;
}

function setParamsForEditFolderModal() {
  // Here we are setting the params for edit folder modal to show the existing values.

  // For agent, team, inboxes,and campaigns we get only the id's from the query.
  // So we are mapping the id's to the actual values.

  // For labels we get the name of the label from the query.
  // If we delete the label from the label list then we will not be able to show the label name.

  // For custom attributes we get only attribute key.
  // So we are mapping it to find the input type of the attribute to show in the edit folder modal.
  return {
    agents: agentList.value,
    teams: teamsList.value,
    inboxes: inboxesList.value,
    labels: labels.value,
    campaigns: campaigns.value,
    languages: languages,
    countries: countries,
    priority: [
      { id: 'low', name: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
      { id: 'medium', name: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
      { id: 'high', name: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
      { id: 'urgent', name: t('CONVERSATION.PRIORITY.OPTIONS.URGENT') },
    ],
    filterTypes: advancedFilterTypes.value,
    allCustomAttributes: conversationCustomAttributes.value,
  };
}

function initializeExistingFilterToModal() {
  const statusFilter = initializeStatusAndAssigneeFilterToModal(
    activeStatus.value,
    currentUserDetails.value,
    activeAssigneeTab.value
  );
  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  if (statusFilter) {
    appliedFilter.value = [...appliedFilter.value, useCamelCase(statusFilter)];
  }

  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  const otherFilters = initializeInboxTeamAndLabelFilterToModal(
    props.conversationInbox,
    inbox.value,
    props.teamId,
    activeTeam.value,
    props.label
  ).map(useCamelCase);

  appliedFilter.value = [...appliedFilter.value, ...otherFilters];
}

function initializeFolderToFilterModal(newActiveFolder) {
  // Here we are setting the params for edit folder modal.
  //  To show the existing values. when we click on edit folder button.

  // Here we get the query from the active folder.
  // And we are mapping the query to the actual values.
  // To show in the edit folder modal by the help of generateValuesForEditCustomViews helper.
  const query = unref(newActiveFolder)?.query?.payload;
  if (!Array.isArray(query)) return;

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    const values = Array.isArray(transformed.values)
      ? generateValuesForEditCustomViews(
          useSnakeCase(filter),
          setParamsForEditFolderModal()
        )
      : [];

    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values,
    };
  });

  appliedFilter.value = [...appliedFilter.value, ...newFilters];
}

function initalizeAppliedFiltersToModal() {
  appliedFilter.value = [...appliedFilters.value];
}

function onToggleAdvanceFiltersModal() {
  if (showAdvancedFilters.value === true) {
    closeAdvanceFiltersModal();
    return;
  }

  if (!hasAppliedFilters.value && !hasActiveFolders.value) {
    initializeExistingFilterToModal();
  }
  if (hasActiveFolders.value) {
    initializeFolderToFilterModal(activeFolder.value);
  }
  if (hasAppliedFilters.value) {
    initalizeAppliedFiltersToModal();
  }

  showAdvancedFilters.value = true;
}

function fetchConversations() {
  store.dispatch('updateChatListFilters', conversationFilters.value);
  store.dispatch('fetchAllConversations').then(emitConversationLoaded);
}

function resetAndFetchData() {
  appliedFilter.value = [];
  resetBulkActions();
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  store.dispatch('clearConversationFilters');
  if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  }
  if (props.foldersId) {
    return;
  }
  fetchConversations();
  // eslint-disable-next-line no-use-before-define
  fetchConversationStats();
}

function loadMoreConversations() {
  if (hasCurrentPageEndReached.value || chatListLoading.value) {
    return;
  }

  if (
    !hasAppliedFiltersOrActiveFolders.value &&
    !conversationList.value.length &&
    activeAssigneeTabCount.value === 0
  ) {
    return;
  }

  if (!hasAppliedFiltersOrActiveFolders.value) {
    fetchConversations();
  } else if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  } else if (hasAppliedFilters.value) {
    fetchFilteredConversations(appliedFilters.value);
  }
}

function updateAssigneeTab(selectedTab) {
  if (activeAssigneeTab.value === selectedTab) return;

  resetBulkActions();
  emitter.emit('clearSearchInput');
  activeAssigneeTab.value = selectedTab;
  resetAndFetchData();
  // eslint-disable-next-line no-use-before-define
  redirectToConversationList(selectedTab, activeStatus.value);
}

function onBasicFilterChange(value, type) {
  if (type === 'status') {
    activeStatus.value = value;
    if (value === wootConstants.STATUS_TYPE.RESOLVED) {
      activeAssigneeTab.value = wootConstants.ASSIGNEE_TYPE.ALL;
    } else if (activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL) {
      activeAssigneeTab.value = wootConstants.ASSIGNEE_TYPE.ME;
    }
  } else {
    activeSortBy.value = value;
  }
  if (type === 'status') {
    // eslint-disable-next-line no-use-before-define
    redirectToConversationList(activeAssigneeTab.value, activeStatus.value);
  }
  resetAndFetchData();
}

function openLastSavedItemInFolder() {
  const lastItemOfFolder = folders.value[folders.value.length - 1];
  const lastItemId = lastItemOfFolder.id;
  router.push({
    name: 'folder_conversations',
    params: { id: lastItemId },
  });
}

function openLastItemAfterDeleteInFolder() {
  if (folders.value.length > 0) {
    openLastSavedItemInFolder();
  } else {
    router.push({ name: 'home' });
    fetchConversations();
  }
}

function redirectToConversationList(
  assigneeView = route.query.view,
  status = route.query.status
) {
  const {
    params: { accountId, inbox_id: inboxId, label, teamId },
    name,
  } = route;

  let conversationType = '';
  if (isOnMentionsView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.MENTION;
  } else if (isOnParticipatingView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.PARTICIPATING;
  } else if (isOnUnattendedView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.UNATTENDED;
  }
  const path = conversationListPageURL({
    accountId,
    conversationType: conversationType,
    customViewId: props.foldersId,
    inboxId,
    label,
    teamId,
  });

  router.push({
    path,
    query: buildConversationFilterQuery({ view: assigneeView, status }),
  });
}

async function assignPriority(priority, conversationId = null) {
  store.dispatch('setCurrentChatPriority', {
    priority,
    conversationId,
  });
  store.dispatch('assignPriority', { conversationId, priority }).then(() => {
    useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
      newValue: priority,
      from: 'Context menu',
    });
    useAlert(
      t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
        priority,
        conversationId,
      })
    );
  });
}

async function markAsUnread(conversationId) {
  try {
    await store.dispatch('markMessagesUnread', {
      id: conversationId,
    });
    redirectToConversationList();
  } catch (error) {
    // Ignore error
  }
}
async function markAsRead(conversationId) {
  try {
    await store.dispatch('markMessagesRead', {
      id: conversationId,
    });
  } catch (error) {
    // Ignore error
  }
}

async function onAssignTeam(team, conversationId = null) {
  try {
    await store.dispatch('assignTeam', {
      conversationId,
      teamId: team.id,
    });
    useAlert(
      t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.SUCCESFUL', {
        team: team.name,
        conversationId,
      })
    );
  } catch (error) {
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED'));
  }
}

function toggleConversationStatus(
  conversationId,
  status,
  snoozedUntil,
  customAttributes = null
) {
  const payload = {
    conversationId,
    status,
    snoozedUntil,
  };

  if (customAttributes) {
    payload.customAttributes = customAttributes;
  }

  store.dispatch('toggleStatus', payload).then(() => {
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
  });
}

function handleResolveConversation(conversationId, status, snoozedUntil) {
  if (status !== wootConstants.STATUS_TYPE.RESOLVED) {
    toggleConversationStatus(conversationId, status, snoozedUntil);
    return;
  }

  // Check for required attributes before resolving
  const conversation = getConversationById.value(conversationId);
  const currentCustomAttributes = conversation?.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(
    currentCustomAttributes
  );

  if (hasMissing) {
    // Pass conversation context through the modal's API
    const conversationContext = {
      id: conversationId,
      snoozedUntil,
    };
    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleConversationStatus(conversationId, status, snoozedUntil);
  }
}

function handleResolveWithAttributes({ attributes, context }) {
  if (context) {
    const existingConversation = getConversationById.value(context.id);
    const currentCustomAttributes =
      existingConversation?.custom_attributes || {};
    const mergedAttributes = { ...currentCustomAttributes, ...attributes };

    toggleConversationStatus(
      context.id,
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
}

function allSelectedConversationsStatus(status) {
  if (!selectedConversations.value.length) return false;
  return selectedConversations.value.every(item => {
    return getConversationById.value(item)?.status === status;
  });
}

function toggleSelectAll(check) {
  selectAllConversations(check, conversationList);
}

async function performConversationStatsRefresh() {
  if (hasAppliedFiltersOrActiveFolders.value) return;
  const statsFilters = {
    inboxId: props.conversationInbox || undefined,
    status: activeStatus.value,
    teamId: props.teamId || undefined,
    conversationType: props.conversationType || undefined,
    labels: props.label ? [props.label] : undefined,
  };

  tabStatsRequestSequence += 1;
  const requestSequence = tabStatsRequestSequence;
  tabStatsError.value = false;
  try {
    const result = await loadConversationStats({
      canonicalBucketsEnabled: canonicalBucketsEnabled.value,
      filters: statsFilters,
      includeBotCounts: !props.label,
      requestMeta: filters => ConversationApi.meta(filters),
    });

    if (requestSequence !== tabStatsRequestSequence) return;
    store.dispatch('conversationStats/set', result.meta);
    botTabCounts.value = result.botTabCounts;
  } catch {
    if (requestSequence === tabStatsRequestSequence) tabStatsError.value = true;
  }
}

const conversationStatsRefresher = createConversationStatsRefresher(
  performConversationStatsRefresh
);

function fetchConversationStats() {
  conversationStatsRefresher.schedule();
}

useEmitter('fetch_conversation_stats', fetchConversationStats);

onMounted(() => {
  store.dispatch('setChatListFilters', conversationFilters.value);
  setFiltersFromUISettings();
  store.dispatch('setChatStatusFilter', activeStatus.value);
  store.dispatch('setChatSortFilter', activeSortBy.value);
  resetAndFetchData();
  if (hasActiveFolders.value) {
    store.dispatch('campaigns/get');
  }
});

onBeforeUnmount(() => {
  tabStatsRequestSequence += 1;
  conversationStatsRefresher.cancel();
});

const deleteConversationDialogRef = ref(null);
const selectedConversationId = ref(null);

async function deleteConversation() {
  try {
    await store.dispatch('deleteConversation', selectedConversationId.value);
    redirectToConversationList();
    selectedConversationId.value = null;
    deleteConversationDialogRef.value.close();
    useAlert(t('CONVERSATION.SUCCESS_DELETE_CONVERSATION'));
  } catch (error) {
    useAlert(t('CONVERSATION.FAIL_DELETE_CONVERSATION'));
  }
}

const handleDelete = conversationId => {
  selectedConversationId.value = conversationId;
  deleteConversationDialogRef.value.open();
};

provide('selectConversation', selectConversation);
provide('deSelectConversation', deSelectConversation);
provide('assignAgent', onAssignAgent);
provide('assignTeam', onAssignTeam);
provide('assignLabels', onAssignLabels);
provide('removeLabels', onRemoveLabels);
provide('updateConversationStatus', handleResolveConversation);
provide('markAsUnread', markAsUnread);
provide('markAsRead', markAsRead);
provide('assignPriority', assignPriority);
provide('isConversationSelected', isConversationSelected);
provide('deleteConversation', handleDelete);

watch(activeTeam, () => resetAndFetchData());

watch(
  computed(() => props.conversationInbox),
  () => resetAndFetchData()
);
watch(
  computed(() => props.label),
  () => resetAndFetchData()
);
watch(
  computed(() => props.conversationType),
  () => resetAndFetchData()
);

watch(
  () => [route.query.view, route.query.status],
  ([view, status]) => {
    const nextStatus =
      normalizeConversationStatus(status) || wootConstants.STATUS_TYPE.OPEN;
    const nextView = normalizeAssigneeView(
      view,
      nextStatus === wootConstants.STATUS_TYPE.RESOLVED
        ? wootConstants.ASSIGNEE_TYPE.ALL
        : wootConstants.ASSIGNEE_TYPE.ME
    );
    const didViewChange = activeAssigneeTab.value !== nextView;
    const didStatusChange = activeStatus.value !== nextStatus;

    if (!didViewChange && !didStatusChange) return;

    activeAssigneeTab.value = nextView;
    activeStatus.value = nextStatus;
    resetBulkActions();
    emitter.emit('clearSearchInput');
    resetAndFetchData();
  }
);

watch(activeFolder, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    store.dispatch('customViews/setActiveConversationFolder', newVal || null);
  }
  resetAndFetchData();
});

watch(chatLists, () => {
  chatsOnView.value = conversationList.value;
});

watch(conversationFilters, (newVal, oldVal) => {
  if (JSON.stringify(newVal) !== JSON.stringify(oldVal)) {
    store.dispatch('updateChatListFilters', newVal);
  }
});
</script>

<template>
  <div
    class="gt-conversation-rail flex flex-col flex-shrink-0 conversations-list-wrap bg-n-surface-1 border-r border-n-weak/70"
    :class="[
      { hidden: !showConversationList },
      isOnExpandedLayout ? 'basis-full' : 'w-[360px] 2xl:w-[404px]',
    ]"
  >
    <slot />
    <ChatListHeader
      :page-title="pageTitle"
      :has-applied-filters="hasAppliedFilters"
      :has-active-folders="hasActiveFolders"
      :active-status="activeStatus"
      :is-on-expanded-layout="isOnExpandedLayout"
      :conversation-stats="conversationStats"
      :is-list-loading="chatListLoading && !conversationList.length"
      @add-folders="onClickOpenAddFoldersModal"
      @delete-folders="onClickOpenDeleteFoldersModal"
      @filters-modal="onToggleAdvanceFiltersModal"
      @reset-filters="resetAndFetchData"
      @basic-filter-change="onBasicFilterChange"
    />

    <TeleportWithDirection
      v-if="showAddFoldersModal"
      to="#saveFilterTeleportTarget"
    >
      <SaveCustomView
        v-model="appliedFilter"
        :custom-views-query="foldersQuery"
        :open-last-saved-item="openLastSavedItemInFolder"
        @close="onCloseAddFoldersModal"
      />
    </TeleportWithDirection>

    <DeleteCustomViews
      v-if="showDeleteFoldersModal"
      v-model:show="showDeleteFoldersModal"
      :active-custom-view="activeFolder"
      :custom-views-id="foldersId"
      :open-last-item-after-delete="openLastItemAfterDeleteInFolder"
      @close="onCloseDeleteFoldersModal"
    />

    <div
      v-if="!hasAppliedFiltersOrActiveFolders"
      class="gt-assignee-tabs px-2 pt-2 pb-1 border-b border-n-weak/70"
    >
      <ChatTypeTabs
        :items="assigneeTabItems"
        :active-tab="activeAssigneeTab"
        class="neo-focus-ring"
        @chat-tab-change="updateAssigneeTab"
      />
    </div>

    <div
      v-if="chatListRequestError || tabStatsError"
      role="alert"
      class="mx-3 mt-3 flex items-center justify-between gap-3 rounded-xl border border-n-ruby-8/40 bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
    >
      <span>{{ $t('CHAT_LIST.LIST.LOAD_ERROR') }}</span>
      <button
        type="button"
        class="neo-focus-ring rounded-md px-2 py-1 font-medium hover:bg-n-alpha-2"
        @click="resetAndFetchData"
      >
        {{ $t('CHAT_LIST.LIST.RETRY') }}
      </button>
    </div>

    <div
      class="resolved-view-toggle mx-2 mt-2 mb-1 px-3 py-2 text-sm font-medium flex justify-between items-center rounded-xl border border-n-weak/70 cursor-pointer hover:bg-n-alpha-1/70 transition-colors"
      :class="isViewingResolved ? 'text-amber-400' : 'text-n-slate-11'"
      @click="toggleResolvedView"
    >
      <span class="flex items-center gap-1.5">
        <span
          :class="
            isViewingResolved
              ? 'i-lucide-arrow-left'
              : 'i-lucide-check-circle text-n-teal-10'
          "
          class="size-3.5"
        />
        {{
          isViewingResolved
            ? $t('CHAT_LIST.RESOLVED_VIEW.BACK')
            : $t('CHAT_LIST.RESOLVED_VIEW.OPEN')
        }}
      </span>
    </div>

    <p
      v-if="!chatListLoading && !conversationList.length"
      class="flex overflow-auto justify-center items-center p-4 mx-3 my-4 rounded-2xl border border-dashed border-n-weak/80 bg-n-surface-2/45 text-n-slate-11 text-center"
    >
      {{ $t('CHAT_LIST.LIST.404') }}
    </p>
    <ConversationBulkActions
      v-if="selectedConversations.length"
      :conversations="selectedConversations"
      :all-conversations-selected="allConversationsSelected"
      :selected-inboxes="uniqueInboxes"
      :show-open-action="allSelectedConversationsStatus('open')"
      :show-resolved-action="allSelectedConversationsStatus('resolved')"
      :show-snoozed-action="allSelectedConversationsStatus('snoozed')"
      @select-all-conversations="toggleSelectAll"
      @assign-agent="onAssignAgent"
      @update-conversations="onUpdateConversations"
      @assign-labels="onAssignLabels"
      @assign-team="onAssignTeamsForBulk"
    />
    <ConversationList
      :conversation-list="conversationList"
      :is-loading="chatListLoading"
      :show-end-of-list-message="showEndOfListMessage"
      :label="label"
      :team-id="teamId"
      :folders-id="foldersId"
      :conversation-type="conversationType"
      :show-assignee="showAssigneeInConversationCard"
      :is-on-expanded-layout="isOnExpandedLayout"
      @load-more="loadMoreConversations"
    />
    <Dialog
      ref="deleteConversationDialogRef"
      type="alert"
      :title="
        $t('CONVERSATION.DELETE_CONVERSATION.TITLE', {
          conversationId: selectedConversationId,
        })
      "
      :description="$t('CONVERSATION.DELETE_CONVERSATION.DESCRIPTION')"
      :confirm-button-label="$t('CONVERSATION.DELETE_CONVERSATION.CONFIRM')"
      @confirm="deleteConversation"
      @close="selectedConversationId = null"
    />
    <TeleportWithDirection
      v-if="showAdvancedFilters"
      to="#conversationFilterTeleportTarget"
    >
      <ConversationFilter
        v-model="appliedFilter"
        :folder-name="activeFolderName"
        :is-folder-view="hasActiveFolders"
        @apply-filter="onApplyFilter"
        @update-folder="onUpdateSavedFilter"
        @close="closeAdvanceFiltersModal"
      />
    </TeleportWithDirection>
    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
  </div>
</template>

<style scoped>
.resolved-view-toggle {
  background-image: linear-gradient(
    135deg,
    rgba(29, 161, 255, 0.07) 0%,
    transparent 100%
  );
}

.gt-assignee-tabs {
  background: radial-gradient(
      ellipse at 50% -40%,
      rgba(29, 161, 255, 0.14),
      transparent 72%
    ),
    rgba(var(--surface-1), 0.72);
}
</style>
