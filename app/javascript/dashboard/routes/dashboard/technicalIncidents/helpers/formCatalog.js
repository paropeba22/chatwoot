export const emptyMetadata = () => ({
  incident_types: [],
  statuses: [],
  severities: [],
  problem_types: [],
  affected_services: [],
  actions: [],
  scope_fields: [],
  scope_operators: [],
  template_variables: [],
});

export const catalogLabel = (option, translate) =>
  option?.label_key ? translate(option.label_key, option.label) : option?.label;

export const createCriterion = (criterionType = 'general') => ({
  criterion_type: criterionType,
  operator: 'in',
  values: [],
});

export const createScopeGroup = position => ({
  position,
  criteria_attributes: [createCriterion()],
});

const normalizeValues = values => {
  if (Array.isArray(values)) return values;
  if (typeof values !== 'string') return [];

  try {
    const parsed = JSON.parse(values);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return values
      .split(/[\n,]/)
      .map(value => value.trim())
      .filter(Boolean);
  }
};

export const hydrateScopeGroups = groups =>
  (groups || []).map(group => ({
    id: group.id,
    position: group.position,
    criteria_attributes: (group.criteria || []).map(criterion => ({
      id: criterion.id,
      criterion_type: criterion.criterion_type,
      operator: criterion.operator,
      values: normalizeValues(criterion.values),
    })),
  }));

export const serializeScopeGroups = groups =>
  groups.map(group => ({
    id: group.id,
    position: group.position,
    _destroy: Reflect.get(group, '_destroy'),
    criteria_attributes: group.criteria_attributes.map(criterion => ({
      id: criterion.id,
      criterion_type: criterion.criterion_type,
      operator: criterion.operator,
      values: normalizeValues(criterion.values),
      _destroy: Reflect.get(criterion, '_destroy'),
    })),
  }));

const activeItems = items =>
  items.filter(item => !Reflect.get(item, '_destroy'));
const catalogValues = options => new Set(options.map(option => option.value));

const validCriterionValues = (criterion, field) => {
  if (!field) return false;
  if (field.value_type === 'none') return criterion.values.length === 0;
  if (!Array.isArray(criterion.values) || !criterion.values.length)
    return false;
  if (field.value_type === 'catalog_multi_select') {
    const allowed = catalogValues(field.available_values || []);
    return criterion.values.every(value => allowed.has(value));
  }
  if (field.value_type === 'location_pairs') {
    return criterion.values.every(value =>
      field.value_fields.every(name => String(value?.[name] || '').trim())
    );
  }
  if (criterion.criterion_type === 'postal_code') {
    return criterion.values.every(
      value => String(value).replace(/\D/g, '').length === 8
    );
  }
  return criterion.values.every(value => {
    const normalized = String(value || '').trim();
    return normalized.length > 0 && normalized.length <= 200;
  });
};

export const validateIncidentForm = (form, metadata) => {
  const errors = [];
  const requireCatalogValue = (field, options, code) => {
    if (!catalogValues(options).has(field)) errors.push(code);
  };

  if (!form.title.trim()) errors.push('TITLE_REQUIRED');
  requireCatalogValue(
    form.incident_type,
    metadata.incident_types,
    'TYPE_REQUIRED'
  );
  requireCatalogValue(form.severity, metadata.severities, 'SEVERITY_REQUIRED');
  requireCatalogValue(form.action, metadata.actions, 'ACTION_REQUIRED');
  const validProblems = catalogValues(metadata.problem_types);
  const validServices = catalogValues(metadata.affected_services);
  if (
    !form.problem_types.length ||
    form.problem_types.some(value => !validProblems.has(value))
  ) {
    errors.push('PROBLEM_TYPES_REQUIRED');
  }
  if (
    !form.affected_services.length ||
    form.affected_services.some(value => !validServices.has(value))
  ) {
    errors.push('SERVICES_REQUIRED');
  }
  if (
    !Number.isInteger(form.priority) ||
    form.priority < 0 ||
    form.priority > 100
  ) {
    errors.push('PRIORITY_INVALID');
  }
  if (form.action !== 'handoff_only' && !form.customer_message.trim()) {
    errors.push('MESSAGE_REQUIRED');
  }

  const startsAt = form.starts_at ? new Date(form.starts_at) : null;
  const expiresAt = form.expires_at ? new Date(form.expires_at) : null;
  const reviewAt = form.review_at ? new Date(form.review_at) : null;
  if (
    [startsAt, expiresAt, reviewAt].some(
      date => date && Number.isNaN(date.getTime())
    )
  ) {
    errors.push('INVALID_DATE');
  }
  if (startsAt && expiresAt && expiresAt <= startsAt)
    errors.push('INVALID_EXPIRATION');
  if (
    startsAt &&
    expiresAt &&
    expiresAt > new Date(startsAt.getTime() + 7 * 24 * 60 * 60 * 1000)
  ) {
    errors.push('INVALID_EXPIRATION');
  }
  if (reviewAt && expiresAt && reviewAt > expiresAt)
    errors.push('INVALID_REVIEW');

  const groups = activeItems(form.scope_groups_attributes);
  if (!groups.length) errors.push('SCOPE_GROUP_REQUIRED');
  groups.forEach(group => {
    const criteria = activeItems(group.criteria_attributes);
    if (!criteria.length) errors.push('SCOPE_CRITERION_REQUIRED');
    const types = criteria.map(criterion => criterion.criterion_type);
    if (new Set(types).size !== types.length)
      errors.push('DUPLICATE_SCOPE_FIELD');
    criteria.forEach(criterion => {
      const field = metadata.scope_fields.find(
        item => item.value === criterion.criterion_type
      );
      if (!field) errors.push('SCOPE_FIELD_REQUIRED');
      if (!field?.allowed_operators.includes(criterion.operator))
        errors.push('SCOPE_OPERATOR_INVALID');
      if (!validCriterionValues(criterion, field))
        errors.push('SCOPE_VALUE_REQUIRED');
    });
  });

  return [...new Set(errors)];
};
