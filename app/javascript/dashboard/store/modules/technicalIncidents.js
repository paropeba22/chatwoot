import TechnicalIncidentsAPI from 'dashboard/api/technicalIncidents';

export const state = {
  records: [],
  current: null,
  options: {},
  meta: {},
  uiFlags: { fetching: false, saving: false, transitioning: false },
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
    const { data } = await TechnicalIncidentsAPI.options();
    commit('SET_OPTIONS', data);
    return data;
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
