import SgpAPIClient from '../../integrations/sgp';
import ApiClient from '../../ApiClient';

describe('#SgpAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    post: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
  });

  afterEach(() => {
    window.axios = originalAxios;
    vi.clearAllMocks();
  });

  it('creates an account-scoped request without exposing SGP configuration', () => {
    expect(SgpAPIClient).toBeInstanceOf(ApiClient);

    SgpAPIClient.perform(42, {
      action: 'consultar_sgp_por_cpf',
      cpf_cnpj: '52998224725',
    });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/conversations/42/sgp',
      {
        action: 'consultar_sgp_por_cpf',
        cpf_cnpj: '52998224725',
      }
    );
  });
});
