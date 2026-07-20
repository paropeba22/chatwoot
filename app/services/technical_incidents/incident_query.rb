class TechnicalIncidents::IncidentQuery
  BUCKETS = {
    'active' => %w[active monitoring],
    'scheduled' => %w[scheduled],
    'history' => %w[resolved expired cancelled]
  }.freeze
  ENUM_FILTERS = {
    status: TechnicalIncident::STATUSES,
    severity: TechnicalIncident::SEVERITIES,
    category: TechnicalIncident::INCIDENT_TYPES,
    service: TechnicalIncident::SERVICE_KEYS,
    scope_type: TechnicalIncidentScopeCriterion::TYPES
  }.freeze

  def initialize(scope, params)
    @scope = scope
    @params = params
    @times = {}
  end

  def valid?
    valid_bucket? && valid_enums? && valid_times?
  rescue ArgumentError
    false
  end

  def call
    filtered = apply_scalar_filters(@scope)
    filtered = apply_service(filtered)
    filtered = apply_text(filtered)
    filtered = apply_times(filtered)
    apply_scope_type(filtered)
  end

  private

  def valid_bucket?
    @params[:bucket].blank? || BUCKETS.key?(@params[:bucket])
  end

  def valid_enums?
    ENUM_FILTERS.all? do |key, allowed|
      @params[key].blank? || allowed.include?(@params[key])
    end
  end

  def valid_times?
    %i[from to].each { |key| parsed_time(key) if @params[key].present? }
    true
  end

  def apply_scalar_filters(scope)
    scope = scope.where(status: BUCKETS.fetch(@params[:bucket])) if @params[:bucket].present?
    scope = scope.where(status: @params[:status]) if @params[:status].present?
    scope = scope.where(severity: @params[:severity]) if @params[:severity].present?
    scope = scope.where(incident_type: @params[:category]) if @params[:category].present?
    scope = scope.where(created_by_id: @params[:creator_id]) if @params[:creator_id].present?
    scope
  end

  def apply_service(scope)
    return scope if @params[:service].blank?

    scope.where('affected_services @> ARRAY[?]::text[]', @params[:service])
  end

  def apply_text(scope)
    return scope if @params[:q].blank?

    query = ActiveRecord::Base.sanitize_sql_like(@params[:q].to_s.first(200))
    scope.where('title ILIKE ?', "%#{query}%")
  end

  def apply_times(scope)
    scope = scope.where('starts_at >= ?', parsed_time(:from)) if @params[:from].present?
    scope = scope.where('starts_at <= ?', parsed_time(:to)) if @params[:to].present?
    scope
  end

  def apply_scope_type(scope)
    return scope if @params[:scope_type].blank?

    scope.joins(scope_groups: :criteria)
         .where(technical_incident_scope_criteria: { criterion_type: @params[:scope_type] })
         .distinct
  end

  def parsed_time(key)
    @times[key] ||= Time.zone.iso8601(@params[key].to_s)
  end
end
