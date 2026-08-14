import axios from 'axios';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import TechnicalIncidentsAPI from '../technicalIncidents';

vi.mock('axios');
global.axios = axios;

describe('TechnicalIncidentsAPI', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.history.pushState({}, '', '/app/accounts/1/technical-incidents/new');
  });

  it('fetches the account-scoped incident form options', () => {
    TechnicalIncidentsAPI.fetchOptions();

    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/technical_incidents/options'
    );
  });
});
