import { flushPromises, mount } from '@vue/test-utils';
import SgpPanel from '../SgpPanel.vue';
import SgpAPI from 'dashboard/api/integrations/sgp';

const dispatch = vi.fn(() => Promise.resolve());

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params = {}) => {
      if (key === 'CONVERSATION.SGP.INVOICE_SUMMARY') {
        return `${params.date} · ${params.value}`;
      }
      return key;
    },
  }),
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

  it('renders plan and invoice summaries from custom attributes', () => {
    const wrapper = mount(SgpPanel, {
      props: {
        conversationId: 42,
        contact: {
          ...contact,
          custom_attributes: {
            sgp_cpf_cnpj: '52998224725',
            sgp_plano: '600 Mega',
            sgp_faturas: [
              {
                id: '1',
                numero: '1001',
                vencimento: '2026-06-15',
                valor: '60.00',
                pix_disponivel: true,
              },
              {
                id: '2',
                numero: '1002',
                vencimento: '2026-07-15',
                valor: '70.00',
                pix_disponivel: true,
              },
            ],
          },
        },
      },
    });

    expect(wrapper.text()).toContain('600 Mega');
    expect(wrapper.text()).toContain('15/06/2026');
    expect(wrapper.text()).toContain('R$ 60,00');
  });

  it('asks for an invoice when a financial action has multiple options', async () => {
    SgpAPI.perform.mockResolvedValue({
      data: { ok: true, message: 'Pix enviado.' },
    });
    const wrapper = mount(SgpPanel, {
      props: {
        conversationId: 42,
        contact: {
          ...contact,
          custom_attributes: {
            sgp_cpf_cnpj: '52998224725',
            sgp_faturas: [
              {
                id: '1',
                numero: '1001',
                vencimento: '2026-06-15',
                valor: '60.00',
                pix_disponivel: true,
              },
              {
                id: '2',
                numero: '1002',
                vencimento: '2026-07-15',
                valor: '70.00',
                pix_disponivel: true,
              },
            ],
          },
        },
      },
    });

    await wrapper.get('[data-testid="sgp-action-pix"]').trigger('click');
    expect(wrapper.find('[data-testid="sgp-invoice-selector"]').exists()).toBe(
      true
    );

    const radios = wrapper.findAll('input[type="radio"]');
    await radios[1].setValue();
    const sendButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('CONVERSATION.SGP.SEND'));
    await sendButton.trigger('click');
    await flushPromises();

    expect(SgpAPI.perform).toHaveBeenCalledWith(42, {
      sgp_action: 'enviar_pix',
      fatura_id: '2',
    });
  });

  it('requests a payment promise only after confirmation', async () => {
    SgpAPI.perform.mockResolvedValue({
      data: { ok: true, message: 'Promessa liberada.' },
    });
    const wrapper = mount(SgpPanel, {
      props: {
        conversationId: 42,
        contact: {
          ...contact,
          custom_attributes: { sgp_cpf_cnpj: '52998224725' },
        },
      },
    });

    await wrapper
      .get('[data-testid="sgp-action-payment-promise"]')
      .trigger('click');
    expect(
      wrapper.find('[data-testid="sgp-promise-confirmation"]').exists()
    ).toBe(true);

    const confirmButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('CONVERSATION.SGP.CONFIRM'));
    await confirmButton.trigger('click');
    await flushPromises();

    expect(SgpAPI.perform).toHaveBeenCalledWith(42, {
      sgp_action: 'liberar_promessa_2_dias',
    });
  });
});
