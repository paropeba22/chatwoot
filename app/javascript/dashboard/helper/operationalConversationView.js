const CANONICAL_BUCKET_BY_VIEW = {
  me: 'mine',
  unassigned: 'human_queue',
  bot: 'bia',
};

export const getCanonicalBucketForView = view => CANONICAL_BUCKET_BY_VIEW[view];

export const filterByCanonicalOperationalView = (conversations, view) => {
  if (view === 'all') return [...conversations];

  const expectedBucket = getCanonicalBucketForView(view);
  return conversations.filter(
    conversation => conversation.operational_bucket === expectedBucket
  );
};
