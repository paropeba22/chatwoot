import { convertToMp3 } from './mp3ConversionUtils';

const mocks = vi.hoisted(() => ({
  audioContext: null,
  workers: [],
}));

class WorkerMock {
  constructor(url, options) {
    this.url = url;
    this.options = options;
    this.postMessage = vi.fn();
    this.terminate = vi.fn();
    mocks.workers.push(this);
  }
}

describe('MP3 conversion worker', () => {
  beforeEach(() => {
    mocks.workers = [];
    mocks.audioContext = {
      decodeAudioData: vi.fn().mockResolvedValue({
        numberOfChannels: 2,
        sampleRate: 48000,
        getChannelData: channel =>
          channel === 0
            ? new Float32Array([0, 0.25, -0.25])
            : new Float32Array([0.5, -0.5, 0]),
      }),
      close: vi.fn().mockResolvedValue(),
    };
    window.AudioContext = vi.fn(() => mocks.audioContext);
    vi.stubGlobal('Worker', WorkerMock);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('transfers decoded channel buffers to a module worker', async () => {
    const input = {
      arrayBuffer: vi.fn().mockResolvedValue(new ArrayBuffer(8)),
    };
    const conversion = convertToMp3(input);

    await vi.waitFor(() => expect(mocks.workers).toHaveLength(1));
    const worker = mocks.workers[0];
    const [message, transferables] = worker.postMessage.mock.calls[0];

    expect(worker.options).toEqual({ type: 'module' });
    expect(message).toMatchObject({ sampleRate: 48000, bitrate: 128 });
    expect(message.channelBuffers).toHaveLength(2);
    expect(transferables).toEqual(message.channelBuffers);
    expect(transferables.every(buffer => buffer instanceof ArrayBuffer)).toBe(
      true
    );

    const encodedBytes = new Uint8Array([0xff, 0xfb, 0x90, 0x64]);
    worker.onmessage({ data: { mp3Buffer: encodedBytes.buffer } });

    const result = await conversion;
    expect(result).toBeInstanceOf(Blob);
    expect(result.type).toBe('audio/mp3');
    expect(result.size).toBe(encodedBytes.byteLength);
    expect(worker.terminate).toHaveBeenCalledOnce();
    expect(mocks.audioContext.close).toHaveBeenCalledOnce();
  });

  it('terminates the worker and releases AudioContext after an encoding error', async () => {
    const conversion = convertToMp3({
      arrayBuffer: vi.fn().mockResolvedValue(new ArrayBuffer(8)),
    });

    await vi.waitFor(() => expect(mocks.workers).toHaveLength(1));
    const worker = mocks.workers[0];
    worker.onerror(new Event('error'));

    await expect(conversion).rejects.toThrow('Conversion to MP3 failed.');
    expect(worker.terminate).toHaveBeenCalledOnce();
    expect(mocks.audioContext.close).toHaveBeenCalledOnce();
  });

  it('rejects a malformed worker response instead of creating an invalid file', async () => {
    const conversion = convertToMp3({
      arrayBuffer: vi.fn().mockResolvedValue(new ArrayBuffer(8)),
    });

    await vi.waitFor(() => expect(mocks.workers).toHaveLength(1));
    mocks.workers[0].onmessage({ data: {} });

    await expect(conversion).rejects.toThrow('Conversion to MP3 failed.');
    expect(mocks.workers[0].terminate).toHaveBeenCalledOnce();
  });
});
