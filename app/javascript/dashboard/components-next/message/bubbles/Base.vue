<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const { variant, orientation, inReplyTo, shouldGroupWithNext } =
  useMessageContext();
const { t } = useI18n();

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]:
    'bg-n-blue-4/65 dark:bg-n-blue-5/50 text-n-slate-12 border border-n-blue-8/25',
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-amber-4/70 dark:bg-n-amber-5/45 text-n-amber-12 border border-n-amber-8/45 shadow-[inset_3px_0_0_rgba(255,197,61,0.65)] [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]:
    'bg-n-surface-2 text-n-slate-12 border border-n-weak/80',
  [MESSAGE_VARIANTS.ACTIVITY]:
    'bg-n-alpha-1/55 text-n-slate-10 text-xs border border-n-weak/40',
  [MESSAGE_VARIANTS.BOT]:
    'bg-n-teal-4/50 dark:bg-n-teal-5/40 text-n-slate-12 border border-n-teal-8/35',
  [MESSAGE_VARIANTS.TEMPLATE]:
    'bg-n-iris-4/55 dark:bg-n-iris-5/45 text-n-slate-12 border border-n-iris-8/35',
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-[14px] ltr:rounded-bl-md rtl:rounded-br-md shadow-[0_3px_12px_rgba(2,8,20,0.16)]',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-[14px] ltr:rounded-br-md rtl:rounded-bl-md shadow-[0_4px_14px_rgba(2,8,20,0.18)]',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
  } else {
    classToApply.push('rounded-lg');
  }

  return classToApply;
});

const scrollToMessage = () => {
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: inReplyTo.value.id,
  });
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    !shouldGroupWithNext.value &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);

const replyToPreview = computed(() => {
  if (!inReplyTo) return '';

  const { content, attachments } = inReplyTo.value;

  if (content) return new MessageFormatter(content).formattedMessage;
  if (attachments?.length) {
    const firstAttachment = attachments[0];
    const fileType = firstAttachment.fileType ?? firstAttachment.file_type;

    return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);
  }

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});
</script>

<template>
  <div
    class="text-sm select-text"
    :class="[
      messageClass,
      {
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <div
      v-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-lg cursor-pointer bg-n-alpha-black1"
      @click="scrollToMessage"
    >
      <div
        v-dompurify-html="replyToPreview"
        class="prose prose-bubble line-clamp-2"
      />
    </div>
    <slot />
    <MessageMeta
      v-if="shouldShowMeta"
      :class="[
        flexOrientationClass,
        variant === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : '',
        variant === MESSAGE_VARIANTS.PRIVATE
          ? 'text-n-amber-12/50'
          : 'text-n-slate-11',
      ]"
      class="mt-2"
    />
  </div>
</template>
