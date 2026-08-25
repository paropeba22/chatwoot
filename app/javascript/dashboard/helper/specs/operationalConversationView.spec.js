import {
  filterByCanonicalOperationalView,
  getCanonicalBucketForView,
  getConversationViewRequestFilters,
} from '../operationalConversationView';

const conversations = [
  { id: 1, operational_bucket: 'mine' },
  { id: 2, operational_bucket: 'human_queue' },
  { id: 3, operational_bucket: 'bia' },
  { id: 4, operational_bucket: null },
  { id: 5 },
];

describe('operationalConversationView', () => {
  it.each([
    ['me', 'mine', [1]],
    ['unassigned', 'human_queue', [2]],
    ['bot', 'bia', [3]],
  ])('keeps %s strict to %s', (view, bucket, expectedIds) => {
    expect(getCanonicalBucketForView(view)).toBe(bucket);
    expect(
      filterByCanonicalOperationalView(conversations, view).map(({ id }) => id)
    ).toEqual(expectedIds);
  });

  it('keeps every authorized conversation in the all view', () => {
    expect(
      filterByCanonicalOperationalView(conversations, 'all').map(({ id }) => id)
    ).toEqual([1, 2, 3, 4, 5]);
  });

  it.each([
    ['me', 'me', 'mine'],
    ['unassigned', 'unassigned', 'human_queue'],
    ['bot', 'all', 'bia'],
    ['all', 'all', undefined],
  ])(
    'builds the %s request without changing its operational scope',
    (view, assigneeType, operationalBucket) => {
      expect(getConversationViewRequestFilters(view)).toEqual({
        assigneeType,
        operationalBucket,
      });
    }
  );
});
