const BOT_LABEL = 'bot-bia';

export const CONVERSATION_STATS_REFRESH_DELAY = 200;

export const createConversationStatsRefresher = (
  refresh,
  { delay = CONVERSATION_STATS_REFRESH_DELAY } = {}
) => {
  let timerId;
  let inFlight;
  let requestedRevision = 0;
  let cancelled = false;

  const run = async () => {
    if (cancelled) return undefined;
    if (inFlight) return inFlight;

    const revision = requestedRevision;
    const request = Promise.resolve().then(refresh);
    inFlight = request;

    try {
      return await request;
    } finally {
      if (inFlight === request) inFlight = undefined;
      if (!cancelled && requestedRevision > revision && !timerId) {
        timerId = setTimeout(() => {
          timerId = undefined;
          run();
        }, delay);
      }
    }
  };

  const scheduleTimer = () => {
    clearTimeout(timerId);
    timerId = setTimeout(() => {
      timerId = undefined;
      run();
    }, delay);
  };

  return {
    schedule() {
      requestedRevision += 1;
      scheduleTimer();
    },
    flush() {
      clearTimeout(timerId);
      timerId = undefined;
      return run();
    },
    cancel() {
      cancelled = true;
      clearTimeout(timerId);
      timerId = undefined;
    },
  };
};

const responseMeta = response => response?.data?.meta || {};

export const loadConversationStats = async ({
  canonicalBucketsEnabled,
  filters,
  includeBotCounts,
  requestMeta,
}) => {
  if (!includeBotCounts) {
    const response = await requestMeta(filters);
    return {
      meta: responseMeta(response),
      botTabCounts: { total: 0, unassigned: 0 },
    };
  }

  if (canonicalBucketsEnabled) {
    const response = await requestMeta({
      ...filters,
      assigneeType: 'all',
    });
    const meta = responseMeta(response);
    const buckets = meta.operational_buckets;
    if (!buckets) throw new Error('operational_bucket_counts_missing');

    return {
      meta,
      botTabCounts: {
        total: Number(buckets.bia || 0),
        unassigned: 0,
        mine: Number(buckets.mine || 0),
        humanQueue: Number(buckets.human_queue || 0),
      },
    };
  }

  const botFilters = { ...filters, labels: [BOT_LABEL] };
  const [statsResponse, allBotResponse, unassignedBotResponse] =
    await Promise.all([
      requestMeta(filters),
      requestMeta({ ...botFilters, assigneeType: 'all' }),
      requestMeta({ ...botFilters, assigneeType: 'unassigned' }),
    ]);

  return {
    meta: responseMeta(statsResponse),
    botTabCounts: {
      total: Number(responseMeta(allBotResponse).all_count || 0),
      unassigned: Number(
        responseMeta(unassignedBotResponse).unassigned_count || 0
      ),
    },
  };
};
