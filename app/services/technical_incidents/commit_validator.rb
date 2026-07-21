class TechnicalIncidents::CommitValidator
  def initialize(account:, evaluation:, incident:)
    @account = account
    @evaluation = evaluation
    @incident = incident
  end

  def validate!
    validate_switches!
    validate_evaluation!
    validate_accounts!
    validate_actor!
    validate_semantics!
    TechnicalIncidents::IncidentValidator.new(@incident).validate!
    validate_scope!
  end

  private

  def validate_switches!
    reject!('feature_disabled') unless @account.feature_enabled?('technical_incidents')
    reject!('server_automation_not_active') unless TechnicalIncidents::Configuration.automation_mode == 'active'
    reject!('outbox_disabled') unless TechnicalIncidents::Configuration.outbox_enabled?
  end

  def validate_evaluation!
    reject!('evaluation_not_active_mode') unless @evaluation.mode == 'active'
    reject!('evaluation_expired') if @evaluation.stale?
    reject!('evaluation_not_matched') unless @evaluation.status.in?(%w[general_match matched])
    validate_incident_snapshot!
    reject!('selected_contract_missing') if selected_contract_required?
  end

  def validate_incident_snapshot!
    reject!('incident_unavailable') unless @incident&.active_and_current?
    reject!('notification_version_changed') unless snapshot_version == @incident.notification_version
  end

  def validate_accounts!
    account_ids = [@evaluation.account_id, @incident.account_id, @evaluation.conversation.account_id]
    reject!('account_mismatch') unless account_ids.all?(@account.id)
  end

  def validate_actor!
    reject!('automation_actor_missing') unless @evaluation.agent_bot
    valid_actor = @evaluation.agent_bot.account_id == @account.id &&
                  @evaluation.agent_bot.bot_config.to_h['technical_incidents_api'] == true
    reject!('automation_actor_invalid') unless valid_actor
  end

  def validate_semantics!
    compatible = TechnicalIncidents::SemanticFilter.compatible?(@incident, @evaluation.classification)
    reject!('semantic_compatibility_changed') unless compatible

    allowed = TechnicalIncidents::SemanticGate.allowed_match_source?(@evaluation.classification, match_source)
    reject!('semantic_gate_rejected') unless allowed
  end

  def validate_scope!
    return validate_general_scope! if @evaluation.status == 'general_match'

    match = TechnicalIncidents::Matcher.new(
      incident: @incident,
      contract: @evaluation.selected_contract,
      classification: @evaluation.classification
    ).call
    reject!('deterministic_match_changed') unless match
    reject!('match_source_changed') unless match[:match_source] == @evaluation.match_source
  end

  def validate_general_scope!
    reject!('general_scope_changed') unless @incident.general_scope?
  end

  def selected_contract_required?
    @evaluation.status == 'matched' && @evaluation.selected_contract['contract_id'].blank?
  end

  def snapshot_version
    snapshot = Array(@evaluation.candidate_snapshot).find do |candidate|
      candidate['id'] == @evaluation.technical_incident_id
    end
    snapshot&.fetch('notification_version', nil)
  end

  def match_source
    @evaluation.status == 'general_match' ? 'general' : @evaluation.match_source
  end

  def reject!(reason_code)
    raise TechnicalIncidents::CommitService::StaleEvaluation, reason_code
  end
end
