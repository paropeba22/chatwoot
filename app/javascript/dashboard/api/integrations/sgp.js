/* global axios */

import ApiClient from '../ApiClient';

class SgpAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  perform(conversationId, payload) {
    return axios.post(`${this.url}/${conversationId}/sgp`, payload);
  }
}

export default new SgpAPI();
