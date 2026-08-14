<script setup>
import getUuid from 'widget/helpers/uuid';
import { ref, onMounted, onUnmounted, defineEmits, defineExpose } from 'vue';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import { format, intervalToDuration } from 'date-fns';
import { convertAudio } from './utils/mp3ConversionUtils';

const props = defineProps({
  audioRecordFormat: {
    type: String,
    required: true,
  },
});

const emit = defineEmits([
  'recorderProgressChanged',
  'finishRecord',
  'recordingError',
  'pause',
  'play',
]);

const waveformContainer = ref(null);
const wavesurfer = ref(null);
const record = ref(null);
const isRecording = ref(false);
const isPlaying = ref(false);
const hasRecording = ref(false);
const isProcessing = ref(false);
const recordingUrl = ref(null);
let conversionPromise = null;
let isUnmounted = false;

const revokeRecordingUrl = () => {
  if (recordingUrl.value) {
    URL.revokeObjectURL(recordingUrl.value);
    recordingUrl.value = null;
  }
};

const formatTimeProgress = time => {
  const duration = intervalToDuration({ start: 0, end: time });
  return format(
    new Date(0, 0, 0, 0, duration.minutes, duration.seconds),
    'mm:ss'
  );
};

const initWaveSurfer = () => {
  wavesurfer.value = WaveSurfer.create({
    container: waveformContainer.value,
    waveColor: '#1F93FF',
    progressColor: '#6E6F73',
    height: 100,
    barWidth: 2,
    barGap: 1,
    barRadius: 2,
    plugins: [
      RecordPlugin.create({
        scrollingWaveform: true,
        renderRecordedAudio: false,
      }),
    ],
  });

  wavesurfer.value.on('pause', () => emit('pause'));
  wavesurfer.value.on('play', () => emit('play'));

  record.value = wavesurfer.value.plugins[0];

  wavesurfer.value.on('finish', () => {
    isPlaying.value = false;
  });

  record.value.on('record-end', async blob => {
    if (conversionPromise || hasRecording.value) return;

    isProcessing.value = true;
    conversionPromise = convertAudio(blob, props.audioRecordFormat);

    try {
      const audioBlob = await conversionPromise;
      if (isUnmounted) return;

      revokeRecordingUrl();
      recordingUrl.value = URL.createObjectURL(blob);
      const fileName = `${getUuid()}.mp3`;
      const file = new File([audioBlob], fileName, {
        type: props.audioRecordFormat,
      });
      await wavesurfer.value.load(recordingUrl.value);
      if (isUnmounted) return;

      emit('finishRecord', {
        name: file.name,
        type: file.type,
        size: file.size,
        file,
      });
      hasRecording.value = true;
    } catch (error) {
      if (!isUnmounted) {
        hasRecording.value = false;
        emit('recordingError');
      }
    } finally {
      conversionPromise = null;
      isProcessing.value = false;
      isRecording.value = false;
    }
  });

  record.value.on('record-progress', time => {
    emit('recorderProgressChanged', formatTimeProgress(time));
  });
};

const stopRecording = () => {
  if (!isRecording.value || isProcessing.value) return;

  isProcessing.value = true;
  try {
    record.value.stopRecording();
  } catch (error) {
    isProcessing.value = false;
    isRecording.value = false;
    emit('recordingError');
  }
};

const startRecording = () => {
  if (isProcessing.value || isRecording.value) return;

  revokeRecordingUrl();
  hasRecording.value = false;
  record.value.startRecording();
  isRecording.value = true;
};

const playPause = () => {
  if (hasRecording.value) {
    wavesurfer.value.playPause();
    isPlaying.value = !isPlaying.value;
  }
};

onMounted(() => {
  initWaveSurfer();
  startRecording();
});

onUnmounted(() => {
  isUnmounted = true;
  revokeRecordingUrl();
  if (wavesurfer.value) {
    wavesurfer.value.destroy();
  }
});

defineExpose({ playPause, stopRecording, record });
</script>

<template>
  <div class="relative w-full">
    <div ref="waveformContainer" class="w-full p-1" />
    <span
      v-if="isProcessing"
      class="absolute inset-0 flex items-center justify-center text-xs pointer-events-none bg-n-surface-2/80 text-n-slate-11"
      role="status"
    >
      {{ $t('CONVERSATION.REPLYBOX.PROCESSING_AUDIO_RECORDING') }}
    </span>
  </div>
</template>
