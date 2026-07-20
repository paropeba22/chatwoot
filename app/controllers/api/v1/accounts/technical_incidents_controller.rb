class Api::V1::Accounts::TechnicalIncidentsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled!
  before_action :set_incident, except: [:index, :create, :options]
  before_action :authorize_action!

  def index
    query = TechnicalIncidents::IncidentQuery.new(incident_scope, params)
    return render_invalid_filters unless query.valid?

    records = paginate(query.call.order(priority: :desc, starts_at: :desc, id: :desc))
    render_paginated(records) { |incident| TechnicalIncidentSerializer.new(incident).as_json }
  end

  def show
    render json: TechnicalIncidentSerializer.new(@incident, include_details: true)
  end

  def create
    @incident = Current.account.technical_incidents.new(incident_params)
    @incident.created_by = Current.user
    @incident.updated_by = Current.user
    TechnicalIncidents::IncidentValidator.new(@incident).validate!
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
      params.permit(:expires_at, :review_at, :estimated_resolution_at, :lock_version)
    )
    render json: TechnicalIncidentSerializer.new(@incident.reload, include_details: true)
  rescue ActiveRecord::StaleObjectError
    render json: { error: 'record_conflict', current_lock_version: @incident.reload.lock_version }, status: :conflict
  rescue TechnicalIncidents::LifecycleService::InvalidTransition, TechnicalIncidents::TemplateRenderer::InvalidTemplate,
         ActiveRecord::RecordInvalid => e
    render json: { error: 'invalid_transition', reason_code: e.message }, status: :unprocessable_entity
  end

  def history
    paginated = paginate(@incident.updates.order(created_at: :desc, id: :desc))
    render_paginated(paginated) { |update| TechnicalIncidents::UpdatePresenter.new(update).as_json }
  end

  def conversations
    links = paginate(@incident.conversation_links.includes(:conversation).order(created_at: :desc, id: :desc))
    can_audit = policy(@incident).history?
    render_paginated(links) do |link|
      {
        id: link.id,
        conversation_id: link.conversation_id,
        conversation_display_id: link.conversation.display_id,
        contract_reference: TechnicalIncidents::ContractReferencePresenter.call(
          link.contract_reference,
          audit_authorized: can_audit
        ),
        notification_version: link.notification_version,
        created_at: link.created_at
      }
    end
  end

  def evaluations
    evaluations = paginate(@incident.evaluations.order(created_at: :desc, id: :desc))
    render_paginated(evaluations) do |evaluation|
      evaluation.attributes.slice(
        'opaque_id', 'status', 'reason_code', 'match_source', 'operational_confidence',
        'feedback', 'latency_ms', 'created_at'
      )
    end
  end

  def destroy
    if @incident.deletable_draft?
      @incident.transaction do
        @incident.updates.delete_all(:delete_all)
        @incident.destroy!
      end
      return head :ok
    end

    TechnicalIncidents::UpdateService.new(
      incident: @incident,
      attributes: { archived_at: Time.current },
      actor: Current.user
    ).call
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

  def incident_scope
    policy_scope(Current.account.technical_incidents)
      .includes(:created_by, :updated_by, scope_groups: :criteria)
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
    if source.key?(:scope_groups_attributes)
      permitted[:scope_groups_attributes] = TechnicalIncidents::ScopeParamsSanitizer.call(source[:scope_groups_attributes])
    end
    permitted
  end

  def render_invalid_filters
    render json: { error: 'invalid_filters' }, status: :unprocessable_entity
  end

  def paginate(scope)
    page = [params.fetch(:page, 1).to_i, 1].max
    per_page = params.fetch(:per_page, 25).to_i.clamp(1, 100)
    scope.page(page).per(per_page)
  end

  def render_paginated(records, &)
    render json: TechnicalIncidents::PaginatedPresenter.new(records).as_json(&)
  end
end
