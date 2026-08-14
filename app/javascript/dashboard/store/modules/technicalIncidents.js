import TechnicalIncidentsAPI from 'dashboard/api/technicalIncidents';

let optionsRequestSequence = 0;

export const state = {
  records: [],
  current: null,
  options: {
    incident_types: [],
    statuses: [],
    severities: [],
    problem_types: [],
    affected_services: [],
    actions: [],
    scope_fields: [],
    scope_operators: [],
    template_variables: [],
  },
  meta: {},
  uiFlags: {
    fetching: false,
    fetchingOptions: false,
    optionsError: null,
    saving: false,
    transitioning: false,
  },
};

export const getters = {
  getTechnicalIncidents: $state => $state.records,
  getCurrentTechnicalIncident: $state => $state.current,
  getTechnicalIncidentOptions: $state => $state.options,
  getTechnicalIncidentMeta: $state => $state.meta,
  getTechnicalIncidentUIFlags: $state => $state.uiFlags,
};

export const actions = {
  async fetch({ commit }, params) {
    commit('SET_UI_FLAG', { fetching: true });
    try {
      const { data } = await TechnicalIncidentsAPI.list(params);
      commit('SET_RECORDS', data.payload);
      commit('SET_META', data.meta);
      return data;
    } finally {
      commit('SET_UI_FLAG', { fetching: false });
    }
  },
  async show({ commit }, id) {
    commit('SET_UI_FLAG', { fetching: true });
    try {
      const { data } = await TechnicalIncidentsAPI.show(id);
      commit('SET_CURRENT', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { fetching: false });
    }
  },
  async fetchOptions({ commit }) {
    optionsRequestSequence += 1;
    const requestId = optionsRequestSequence;
    commit('SET_UI_FLAG', { fetchingOptions: true, optionsError: null });
    try {
      const { data } = await TechnicalIncidentsAPI.fetchOptions();
      if (requestId === optionsRequestSequence) commit('SET_OPTIONS', data);
      return data;
    } catch (error) {
      if (requestId === optionsRequestSequence) {
        commit('SET_UI_FLAG', {
          optionsError: error?.response?.status || 'request_failed',
        });
      }
      throw error;
    } finally {
      if (requestId === optionsRequestSequence) {
        commit('SET_UI_FLAG', { fetchingOptions: false });
      }
    }
  },
  async create({ commit }, payload) {
    commit('SET_UI_FLAG', { saving: true });
    try {
      const { data } = await TechnicalIncidentsAPI.create({
        technical_incident: payload,
      });
      commit('SET_CURRENT', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { saving: false });
    }
  },
  async update({ commit }, { id, payload }) {
    commit('SET_UI_FLAG', { saving: true });
    try {
      const { data } = await TechnicalIncidentsAPI.update(id, {
        technical_incident: payload,
      });
      commit('SET_CURRENT', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { saving: false });
    }
  },
  async transition({ commit }, { id, status, attributes = {} }) {
    commit('SET_UI_FLAG', { transitioning: true });
    try {
      const { data } = await TechnicalIncidentsAPI.transition(id, {
        status,
        ...attributes,
      });
      commit('SET_CURRENT', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { transitioning: false });
    }
  },
  delete(_, id) {
    return TechnicalIncidentsAPI.delete(id);
  },
};

export const mutations = {
  SET_RECORDS($state, records) {
    $state.records = records;
  },
  SET_CURRENT($state, record) {
    $state.current = record;
  },
  SET_OPTIONS($state, options) {
    $state.options = options;
  },
  SET_META($state, meta) {
    $state.meta = meta;
  },
  SET_UI_FLAG($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
};

export default { namespaced: true, state, getters, actions, mutations };
