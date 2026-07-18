class Api::V1::Accounts::TechnicalIncidentsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled!
  before_action :set_incident, except: [:index, :create, :options]
  before_action :authorize_action!

  def index
    incidents = policy_scope(Current.account.technical_incidents).includes(:created_by, :updated_by, scope_groups: :criteria)
    incidents = apply_filters(incidents).order(priority: :desc, starts_at: :desc, id: :desc)
    page = [params.fetch(:page, 1).to_i, 1].max
    per_page = params.fetch(:per_page, 25).to_i.clamp(1, 100)
    paginated = incidents.page(page).per(per_page)
    render json: {
      payload: paginated.map { |incident| TechnicalIncidentSerializer.new(incident).as_json },
      meta: { current_page: page, per_page: per_page, total_entries: paginated.total_count }
    }
  end

  def show
    render json: TechnicalIncidentSerializer.new(@incident, include_details: true)
  end

  def create
    @incident = Current.account.technical_incidents.new(incident_params)
    @incident.created_by = Current.user
    @incident.updated_by = Current.user
    @incident.save!
    TechnicalIncidents::AuditService.record!(
      incident: @incident, action: 'incident.created', actor: Current.user, origin: 'ui',
      changeset: @incident.attributes.except('internal_note')
    )
    render json: TechnicalIncidentSerializer.new(@incident, include_details: true), status: :created
  end

  def update
    TechnicalIncidents::UpdateService.new(incident: @incident, attributes: incident_params, actor: Current.user).call
    render json: TechnicalIncidentSerializer.new(@incident.reload, include_details: true)
  rescue ActiveRecord::StaleObjectError
    render json: { error: 'record_conflict', current_lock_version: @incident.reload.lock_version }, status: :conflict
  end

  def transition
    ensure_transition_permission!
    TechnicalIncidents::LifecycleService.new(incident: @incident, actor: Current.user).transition!(
      params.require(:status),
      params.permit(:expires_at, :review_at, :estimated_resolution_at)
    )
    render json: TechnicalIncidentSerializer.new(@incident.reload, include_details: true)
  rescue TechnicalIncidents::LifecycleService::InvalidTransition, TechnicalIncidents::TemplateRenderer::InvalidTemplate => e
    render json: { error: 'invalid_transition', reason_code: e.message }, status: :unprocessable_entity
  end

  def history
    render json: @incident.updates.order(created_at: :desc).map { |update| update_payload(update) }
  end

  def conversations
    links = @incident.conversation_links.includes(:conversation).order(created_at: :desc)
    render json: links.map do |link|
      {
        id: link.id,
        conversation_id: link.conversation_id,
        conversation_display_id: link.conversation.display_id,
        contract_reference: link.contract_reference,
        notification_version: link.notification_version,
        created_at: link.created_at
      }
    end
  end

  def evaluations
    render json: @incident.evaluations.order(created_at: :desc).limit(200).map do |evaluation|
      evaluation.attributes.slice(
        'opaque_id', 'status', 'reason_code', 'match_source', 'operational_confidence',
        'feedback', 'latency_ms', 'created_at'
      )
    end
  end

  def destroy
    if @incident.deletable_draft?
      @incident.transaction do
        @incident.updates.delete_all
        @incident.destroy!
      end
      return head :ok
    end

    @incident.update!(archived_at: Time.current, updated_by: Current.user)
    TechnicalIncidents::AuditService.record!(
      incident: @incident, action: 'incident.archived', actor: Current.user, origin: 'ui'
    )
    head :ok
  end

  def options
    render json: {
      incident_types: TechnicalIncident::INCIDENT_TYPES,
      statuses: TechnicalIncident::STATUSES,
      severities: TechnicalIncident::SEVERITIES,
      problem_types: TechnicalIncident::PROBLEM_TYPES,
      service_keys: TechnicalIncident::SERVICE_KEYS,
      actions: TechnicalIncident::ACTIONS,
      scope_types: TechnicalIncidentScopeCriterion::TYPES,
      template_variables: TechnicalIncidents::TemplateRenderer::ALLOWED_VARIABLES
    }
  end

  private

  def set_incident
    @incident = Current.account.technical_incidents.includes(scope_groups: :criteria).find(params[:id])
  end

  def authorize_action!
    target = @incident || TechnicalIncident
    policy_action = case action_name
                    when 'update'
                      eta_only_update? ? :update_eta? : :update?
                    when 'transition'
                      params[:status] == 'resolved' ? :resolve? : :transition?
                    when 'destroy'
                      :archive?
                    else
                      "#{action_name}?".to_sym
                    end
    authorize(target, policy_action, policy_class: TechnicalIncidentPolicy)
  end

  def ensure_feature_enabled!
    render json: { error: 'feature_disabled' }, status: :not_found unless Current.account.feature_enabled?('technical_incidents')
  end

  def ensure_transition_permission!
    permission = case params[:status]
                 when 'resolved' then 'technical_incident_resolve'
                 else params.key?(:estimated_resolution_at) ? 'technical_incident_update_eta' : 'technical_incident_update'
                 end
    return if Current.account_user.administrator? || Current.account_user.permissions.include?(permission)

    raise Pundit::NotAuthorizedError
  end

  def eta_only_update?
    allowed = %w[estimated_resolution_at expires_at review_at lock_version]
    requested = params.fetch(:technical_incident, {}).keys.map(&:to_s)
    requested.present? && (requested - allowed).empty?
  end

  def incident_params
    source = params.require(:technical_incident)
    permitted = source.permit(
      :title, :incident_type, :severity, :priority, :customer_message, :internal_note, :action,
      :starts_at, :expires_at, :review_at, :estimated_resolution_at, :resend_on_next_contact, :lock_version,
      problem_types: [], affected_services: []
    )
    permitted[:scope_groups_attributes] = sanitize_scope_groups(source[:scope_groups_attributes]) if source.key?(:scope_groups_attributes)
    permitted
  end

  def sanitize_scope_groups(raw_groups)
    nested_collection(raw_groups).first(50).map do |raw_group|
      group = raw_group.to_h.stringify_keys
      group.slice('id', 'position', '_destroy').merge(
        'criteria_attributes' => nested_collection(group['criteria_attributes']).first(20).map do |raw_criterion|
          criterion = raw_criterion.to_h.stringify_keys
          criterion.slice('id', 'criterion_type', 'operator', '_destroy').merge(
            'values' => sanitize_scope_values(criterion['values'])
          )
        end
      )
    end
  end

  def sanitize_scope_values(raw_values)
    nested_collection(raw_values).first(200).map do |raw_value|
      if raw_value.respond_to?(:to_h) && !raw_value.is_a?(String)
        raw_value.to_h.stringify_keys.slice('city', 'neighborhood', 'street')
      else
        raw_value.to_s.first(200)
      end
    end
  end

  def nested_collection(value)
    return [] if value.nil?
    return value.values if value.respond_to?(:values) && !value.is_a?(Array)

    Array(value)
  end

  def apply_filters(scope)
    scope = scope.where(status: bucket_statuses(params[:bucket])) if params[:bucket].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(severity: params[:severity]) if params[:severity].present?
    scope = scope.where(incident_type: params[:category]) if params[:category].present?
    scope = scope.where(created_by_id: params[:creator_id]) if params[:creator_id].present?
    scope = scope.where('? = ANY(affected_services)', params[:service]) if params[:service].present?
    scope = scope.where('title ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%") if params[:q].present?
    scope = scope.where('starts_at >= ?', params[:from]) if params[:from].present?
    scope = scope.where('starts_at <= ?', params[:to]) if params[:to].present?
    if params[:scope_type].present?
      scope = scope.joins(scope_groups: :criteria)
                   .where(technical_incident_scope_criteria: { criterion_type: params[:scope_type] })
                   .distinct
    end
    scope
  end

  def bucket_statuses(bucket)
    {
      'active' => %w[active monitoring],
      'scheduled' => %w[scheduled],
      'history' => %w[resolved expired cancelled]
    }.fetch(bucket, TechnicalIncident::STATUSES)
  end

  def update_payload(update)
    {
      id: update.id,
      action: update.action,
      origin: update.origin,
      actor: update.actor && { id: update.actor.id, type: update.actor_type, name: update.actor.try(:name) },
      changeset: update.changeset,
      request_id: update.request_id,
      created_at: update.created_at
    }
  end
end
