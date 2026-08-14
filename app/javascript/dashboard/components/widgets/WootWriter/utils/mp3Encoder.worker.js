/* eslint-disable no-restricted-globals -- self is the Web Worker global */
import lamejs from '@breezystack/lamejs';

const MAX_SAMPLES_PER_FRAME = 1152;

const floatToInt16 = (source, start, end) => {
  const samples = new Int16Array(end - start);

  for (let index = start; index < end; index += 1) {
    const sample = Math.max(-1, Math.min(1, source[index]));
    samples[index - start] = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
  }

  return samples;
};

export const encodeMp3 = ({ channelBuffers, sampleRate, bitrate }) => {
  const channels = channelBuffers.map(buffer => new Float32Array(buffer));
  if (channels.length < 1 || channels.length > 2) {
    throw new Error('MP3 encoding supports mono or stereo audio.');
  }

  const encoder = new lamejs.Mp3Encoder(channels.length, sampleRate, bitrate);
  const output = [];
  const sampleCount = channels[0].length;

  for (let offset = 0; offset < sampleCount; offset += MAX_SAMPLES_PER_FRAME) {
    const end = Math.min(offset + MAX_SAMPLES_PER_FRAME, sampleCount);
    const left = floatToInt16(channels[0], offset, end);
    const right =
      channels.length === 2 ? floatToInt16(channels[1], offset, end) : null;
    const encoded = right
      ? encoder.encodeBuffer(left, right)
      : encoder.encodeBuffer(left);

    if (encoded.length > 0) {
      output.push(new Uint8Array(encoded));
    }
  }

  const remaining = encoder.flush();
  if (remaining.length > 0) {
    output.push(new Uint8Array(remaining));
  }

  const byteLength = output.reduce((total, chunk) => total + chunk.length, 0);
  const mp3 = new Uint8Array(byteLength);
  let writeOffset = 0;
  output.forEach(chunk => {
    mp3.set(chunk, writeOffset);
    writeOffset += chunk.length;
  });

  return mp3.buffer;
};

if (typeof self !== 'undefined') {
  self.onmessage = ({ data }) => {
    try {
      const mp3Buffer = encodeMp3(data);
      self.postMessage({ mp3Buffer }, [mp3Buffer]);
    } catch (error) {
      self.postMessage({
        error: error.message || 'MP3 encoding failed.',
      });
    }
  };
}
