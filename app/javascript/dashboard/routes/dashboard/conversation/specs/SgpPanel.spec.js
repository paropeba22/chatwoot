import { flushPromises, mount } from '@vue/test-utils';
import SgpPanel from '../SgpPanel.vue';
import SgpAPI from 'dashboard/api/integrations/sgp';

const dispatch = vi.fn(() => Promise.resolve());

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));

vi.mock('dashboard/api/integrations/sgp', () => ({
  default: {
    perform: vi.fn(),
  },
}));

const contact = {
  id: 7,
  custom_attributes: {},
  additional_attributes: {
    cpf: '52998224725',
    status_contrato: 'ATIVO',
  },
};

describe('SgpPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('reads custom attributes first and legacy attributes as fallback', () => {
    const wrapper = mount(SgpPanel, {
      props: {
        conversationId: 42,
        contact: {
          ...contact,
          custom_attributes: {
            sgp_cpf_cnpj: '11222333000181',
            sgp_status_contrato: 'BLOQUEADO',
          },
        },
      },
    });

    expect(wrapper.text()).toContain('11222333000181');
    expect(wrapper.text()).toContain('BLOQUEADO');
  });

  it('validates and sends a normalized document through the Chatwoot API', async () => {
    SgpAPI.perform.mockResolvedValue({
      data: { ok: true, message: 'Atualizado' },
    });
    const wrapper = mount(SgpPanel, {
      props: { conversationId: 42, contact },
    });

    await wrapper.get('button').trigger('click');
    await wrapper
      .get('[data-testid="sgp-document-input"]')
      .setValue('529.982.247-25');
    const buttons = wrapper.findAll('button');
    await buttons
      .find(button => button.text().includes('SAVE_AND_CONSULT'))
      .trigger('click');
    await flushPromises();

    expect(SgpAPI.perform).toHaveBeenCalledWith(42, {
      sgp_action: 'consultar_sgp_por_cpf',
      cpf_cnpj: '52998224725',
    });
    expect(dispatch).toHaveBeenCalledWith('contacts/show', { id: 7 });
  });

  it('keeps future financial actions disabled', () => {
    const wrapper = mount(SgpPanel, {
      props: { conversationId: 42, contact },
    });
    const disabledButtons = wrapper.findAll('button[disabled]');

    expect(disabledButtons).toHaveLength(4);
  });
});
