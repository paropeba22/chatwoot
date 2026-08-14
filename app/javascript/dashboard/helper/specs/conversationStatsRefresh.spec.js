import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  createConversationStatsRefresher,
  loadConversationStats,
} from '../conversationStatsRefresh';

describe('conversation stats refresh', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('coalesces the mount and tab refresh triggers into one request', async () => {
    const refresh = vi.fn().mockResolvedValue();
    const refresher = createConversationStatsRefresher(refresh, { delay: 25 });

    refresher.schedule();
    refresher.schedule();
    await vi.advanceTimersByTimeAsync(25);

    expect(refresh).toHaveBeenCalledOnce();
  });

  it('coalesces a short realtime burst and runs at most one request concurrently', async () => {
    let resolveFirst;
    const refresh = vi
      .fn()
      .mockReturnValueOnce(
        new Promise(resolve => {
          resolveFirst = resolve;
        })
      )
      .mockResolvedValueOnce();
    const refresher = createConversationStatsRefresher(refresh, { delay: 25 });

    refresher.schedule();
    await vi.advanceTimersByTimeAsync(25);
    refresher.schedule();
    refresher.schedule();
    await vi.advanceTimersByTimeAsync(25);

    expect(refresh).toHaveBeenCalledOnce();

    resolveFirst();
    await Promise.resolve();
    await vi.advanceTimersByTimeAsync(25);

    expect(refresh).toHaveBeenCalledTimes(2);
  });

  it('uses one canonical metadata request for all operational bucket counts', async () => {
    const requestMeta = vi.fn().mockResolvedValue({
      data: {
        meta: {
          all_count: 9,
          operational_buckets: { mine: 2, human_queue: 3, bia: 4 },
        },
      },
    });

    const result = await loadConversationStats({
      canonicalBucketsEnabled: true,
      filters: { status: 'open' },
      includeBotCounts: true,
      requestMeta,
    });

    expect(requestMeta).toHaveBeenCalledOnce();
    expect(result.botTabCounts).toEqual({
      total: 4,
      unassigned: 0,
      mine: 2,
      humanQueue: 3,
    });
    expect(result.meta.all_count).toBe(9);
  });

  it('preserves the legacy count contract without duplicate refreshes', async () => {
    const requestMeta = vi
      .fn()
      .mockResolvedValueOnce({ data: { meta: { all_count: 12 } } })
      .mockResolvedValueOnce({ data: { meta: { all_count: 5 } } })
      .mockResolvedValueOnce({ data: { meta: { unassigned_count: 4 } } });

    const result = await loadConversationStats({
      canonicalBucketsEnabled: false,
      filters: { status: 'open' },
      includeBotCounts: true,
      requestMeta,
    });

    expect(requestMeta).toHaveBeenCalledTimes(3);
    expect(result.meta.all_count).toBe(12);
    expect(result.botTabCounts).toEqual({ total: 5, unassigned: 4 });
  });
});
