import { shallowMount } from '@vue/test-utils';
import { messageStamp } from 'shared/helpers/timeHelper';
import Activity from '../Activity.vue';

const messageContext = vi.hoisted(() => ({
  content: { value: 'Agent assigned the conversation' },
  createdAt: { value: 1_725_000_000 },
}));

vi.mock('../../provider.js', () => ({
  useMessageContext: () => messageContext,
}));

describe('Activity bubble', () => {
  it('renders the real event timestamp visibly', () => {
    const wrapper = shallowMount(Activity, {
      global: {
        stubs: {
          BaseBubble: { template: '<div><slot /></div>' },
        },
        directives: {
          'dompurify-html': () => {},
        },
      },
    });

    expect(wrapper.get('time').text()).toBe(
      messageStamp(messageContext.createdAt.value)
    );
  });
});
