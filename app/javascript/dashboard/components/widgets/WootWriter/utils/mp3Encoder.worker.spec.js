import { encodeMp3 } from './mp3Encoder.worker';

describe('MP3 encoder worker', () => {
  it('encodes mono PCM channel data into MP3 bytes', () => {
    const samples = new Float32Array(44100);
    for (let index = 0; index < samples.length; index += 1) {
      samples[index] = Math.sin((2 * Math.PI * 440 * index) / 44100) * 0.25;
    }

    const mp3Buffer = encodeMp3({
      channelBuffers: [samples.buffer],
      sampleRate: 44100,
      bitrate: 128,
    });

    expect(mp3Buffer).toBeInstanceOf(ArrayBuffer);
    expect(mp3Buffer.byteLength).toBeGreaterThan(0);
    expect(new Uint8Array(mp3Buffer)[0]).toBe(0xff);
  });
});
