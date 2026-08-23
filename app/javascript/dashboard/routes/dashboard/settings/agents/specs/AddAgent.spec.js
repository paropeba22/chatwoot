import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import AddAgent from '../AddAgent.vue';

describe('AddAgent', () => {
  const createAction = vi.fn();

  const mountComponent = () => {
    const store = createStore({
      modules: {
        agents: {
          namespaced: true,
          getters: {
            getUIFlags: () => ({ isCreating: false }),
          },
          actions: { create: createAction },
        },
        customRole: {
          namespaced: true,
          getters: {
            getCustomRoles: () => [],
          },
        },
      },
    });
    return shallowMount(AddAgent, {
      global: {
        plugins: [store],
        stubs: { 'woot-modal-header': true },
      },
    });
  };

  beforeEach(() => {
    createAction.mockClear();
  });

  it('accepts one simple password and sends a matching confirmation', async () => {
    const wrapper = mountComponent();
    const passwordInputs = wrapper.findAll('input[type="password"]');

    expect(passwordInputs).toHaveLength(1);

    await wrapper.find('input[type="text"]').setValue('New Agent');
    await wrapper.find('input[type="email"]').setValue('agent@example.com');
    await passwordInputs[0].setValue('simplepass');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(createAction).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        name: 'New Agent',
        email: 'agent@example.com',
        password: 'simplepass',
        password_confirmation: 'simplepass',
      })
    );
  });

  it('does not submit a password below the safe minimum', async () => {
    const wrapper = mountComponent();

    await wrapper.find('input[type="text"]').setValue('New Agent');
    await wrapper.find('input[type="email"]').setValue('agent@example.com');
    await wrapper.find('input[type="password"]').setValue('A1!');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(createAction).not.toHaveBeenCalled();
  });
});
