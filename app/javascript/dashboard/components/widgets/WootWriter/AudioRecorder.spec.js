import { nextTick } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import AudioRecorder from './AudioRecorder.vue';

const mocks = vi.hoisted(() => ({
  convertAudio: vi.fn(),
  recordEvents: {},
  waveEvents: {},
  record: null,
  wavesurfer: null,
}));

vi.mock('./utils/mp3ConversionUtils', () => ({
  convertAudio: mocks.convertAudio,
}));

vi.mock('wavesurfer.js/dist/plugins/record.js', () => ({
  default: {
    create: () => mocks.record,
  },
}));

vi.mock('wavesurfer.js', () => ({
  default: {
    create: () => mocks.wavesurfer,
  },
}));

const mountComponent = () =>
  mount(AudioRecorder, {
    props: { audioRecordFormat: 'audio/mp3' },
    global: { mocks: { $t: key => key } },
  });

describe('AudioRecorder', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.recordEvents = {};
    mocks.waveEvents = {};
    mocks.record = {
      on: vi.fn((event, callback) => {
        mocks.recordEvents[event] = callback;
      }),
      startRecording: vi.fn(),
      stopRecording: vi.fn(),
    };
    mocks.wavesurfer = {
      plugins: [mocks.record],
      on: vi.fn((event, callback) => {
        mocks.waveEvents[event] = callback;
      }),
      load: vi.fn().mockResolvedValue(),
      playPause: vi.fn(),
      destroy: vi.fn(),
    };
    vi.stubGlobal('URL', {
      ...URL,
      createObjectURL: vi.fn(() => 'blob:recording'),
      revokeObjectURL: vi.fn(),
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('stops once and starts only one conversion for repeated events', async () => {
    let resolveConversion;
    mocks.convertAudio.mockReturnValue(
      new Promise(resolve => {
        resolveConversion = resolve;
      })
    );
    const wrapper = mountComponent();

    wrapper.vm.stopRecording();
    wrapper.vm.stopRecording();
    expect(mocks.record.stopRecording).toHaveBeenCalledOnce();

    const source = new Blob(['source'], { type: 'audio/webm' });
    const firstEvent = mocks.recordEvents['record-end'](source);
    const duplicateEvent = mocks.recordEvents['record-end'](source);
    expect(mocks.convertAudio).toHaveBeenCalledOnce();
    await nextTick();
    expect(wrapper.get('[role="status"]').text()).toBe(
      'CONVERSATION.REPLYBOX.PROCESSING_AUDIO_RECORDING'
    );

    resolveConversion(new Blob(['mp3'], { type: 'audio/mp3' }));
    await Promise.all([firstEvent, duplicateEvent]);
    await flushPromises();

    await mocks.recordEvents['record-end'](source);

    expect(wrapper.emitted('finishRecord')).toHaveLength(1);
    expect(mocks.convertAudio).toHaveBeenCalledOnce();
    expect(wrapper.emitted('finishRecord')[0][0]).toMatchObject({
      type: 'audio/mp3',
    });
    expect(mocks.wavesurfer.load).toHaveBeenCalledWith('blob:recording');
  });

  it('recovers from conversion failure and can process a later recording', async () => {
    mocks.convertAudio
      .mockRejectedValueOnce(new Error('worker failed'))
      .mockResolvedValueOnce(new Blob(['mp3'], { type: 'audio/mp3' }));
    const wrapper = mountComponent();
    const source = new Blob(['source'], { type: 'audio/webm' });

    await mocks.recordEvents['record-end'](source);
    await flushPromises();
    expect(wrapper.emitted('recordingError')).toHaveLength(1);
    expect(wrapper.emitted('finishRecord')).toBeUndefined();

    await mocks.recordEvents['record-end'](source);
    await flushPromises();
    expect(wrapper.emitted('finishRecord')).toHaveLength(1);
  });

  it('releases the recording URL and WaveSurfer on unmount', async () => {
    mocks.convertAudio.mockResolvedValue(
      new Blob(['mp3'], { type: 'audio/mp3' })
    );
    const wrapper = mountComponent();

    await mocks.recordEvents['record-end'](
      new Blob(['source'], { type: 'audio/webm' })
    );
    await flushPromises();
    wrapper.unmount();

    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:recording');
    expect(mocks.wavesurfer.destroy).toHaveBeenCalledOnce();
  });

  it('recovers when the recorder fails while stopping', () => {
    mocks.record.stopRecording.mockImplementation(() => {
      throw new Error('stop failed');
    });
    const wrapper = mountComponent();

    wrapper.vm.stopRecording();
    wrapper.vm.stopRecording();

    expect(wrapper.emitted('recordingError')).toHaveLength(1);
    expect(mocks.record.stopRecording).toHaveBeenCalledOnce();
  });
});
