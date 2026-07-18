import ApiClient from './ApiClient';

/* global axios */

class TechnicalIncidentsAPI extends ApiClient {
  constructor() {
    super('technical_incidents', { accountScoped: true });
  }

  list(params = {}) {
    return axios.get(this.url, { params });
  }

  options() {
    return axios.get(`${this.url}/options`);
  }

  transition(id, payload) {
    return axios.post(`${this.url}/${id}/transition`, payload);
  }

  history(id) {
    return axios.get(`${this.url}/${id}/history`);
  }

  conversations(id) {
    return axios.get(`${this.url}/${id}/conversations`);
  }

  evaluations(id) {
    return axios.get(`${this.url}/${id}/evaluations`);
  }

  feedback(evaluationId, payload) {
    return axios.post(
      `${this.apiVersion}/technical_incident_evaluations/${evaluationId}/feedback`,
      payload
    );
  }
}

export default new TechnicalIncidentsAPI();
