import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ContactInfo from '../ContactInfo.vue';
import ContactInfoRow from '../ContactInfoRow.vue';

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: false }),
}));

const buildStore = () =>
  createStore({
    modules: {
      contacts: {
        namespaced: true,
        state: () => ({
          uiFlags: {
            isDeleting: false,
            isMerging: false,
          },
        }),
        getters: {
          getUIFlags: state => state.uiFlags,
        },
        actions: {
          fetchContactableInbox: vi.fn(),
        },
      },
    },
  });

const createWrapper = contact =>
  shallowMount(ContactInfo, {
    props: {
      contact: {
        id: 7,
        name: 'Cliente Grupo Telecom',
        additional_attributes: {},
        ...contact,
      },
    },
    global: {
      plugins: [buildStore()],
      mocks: {
        $route: {
          params: {
            accountId: 1,
          },
        },
      },
    },
  });

const renderedValues = wrapper =>
  wrapper.findAllComponents(ContactInfoRow).map(row => row.props('value'));

describe('ContactInfo', () => {
  it('shows one phone number and hides the technical WhatsApp identifier', () => {
    const wrapper = createWrapper({
      phone_number: '+558187323242',
      identifier: '558187323242@s.whatsapp.net',
    });

    expect(renderedValues(wrapper)).toEqual(['+558187323242']);
    expect(wrapper.text()).not.toContain('558187323242@s.whatsapp.net');
    expect(wrapper.text()).not.toContain('CONTACT_PANEL.NOT_AVAILABLE');
  });

  it('hides empty optional fields instead of rendering unavailable labels', () => {
    const wrapper = createWrapper({
      email: '',
      phone_number: '',
      identifier: '',
      additional_attributes: {
        company_name: '',
        location: '',
      },
    });

    expect(wrapper.find('[data-testid="contact-details"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).not.toContain('CONTACT_PANEL.NOT_AVAILABLE');
    expect(wrapper.findComponent({ name: 'VoiceCallButton' }).exists()).toBe(
      false
    );
  });

  it('keeps meaningful contact details when they are populated', () => {
    const wrapper = createWrapper({
      email: 'cliente@grupotelecom.com.br',
      phone_number: '+5581999999999',
      identifier: 'cliente-11560',
      additional_attributes: {
        company_name: 'Grupo Telecom',
        location: 'Recife, PE',
      },
    });

    expect(renderedValues(wrapper)).toEqual([
      'cliente@grupotelecom.com.br',
      '+5581999999999',
      'cliente-11560',
      'Grupo Telecom',
      'Recife, PE',
    ]);
  });

  it('hides identifiers that only duplicate the phone number', () => {
    const wrapper = createWrapper({
      phone_number: '+55 (81) 99999-9999',
      identifier: '5581999999999',
    });

    expect(renderedValues(wrapper)).toEqual(['+55 (81) 99999-9999']);
  });

  it('uses semantic theme classes for the rounded identity card', () => {
    const wrapper = createWrapper({
      phone_number: '+558187323242',
    });
    const card = wrapper.get('[data-testid="contact-identity-card"]');

    expect(card.classes()).toContain('rounded-2xl');
    expect(card.classes()).toContain('border-n-weak/80');
    expect(card.classes()).toContain('bg-n-alpha-1');
  });
});
