class TechnicalIncidents::OutboxValidator
  def initialize(delivery)
    @delivery = delivery
  end

  def validate!
    validate_switches!
    validate_accounts!
    validate_evaluation!
    validate_incident!
    validate_semantics!
  end

  private

  def validate_switches!
    raise_terminal('feature_disabled') unless @delivery.account.feature_enabled?('technical_incidents')
    unless TechnicalIncidents::Configuration.automation_mode == 'active'
      raise_disabled('server_automation_not_active')
    end
    raise_disabled('delivery_disabled') unless TechnicalIncidents::Configuration.delivery_enabled?
  end

  def validate_accounts!
    ids = [incident.account_id, evaluation.account_id, @delivery.conversation.account_id]
    raise_terminal('account_mismatch') unless ids.all?(@delivery.account_id)
  end

  def validate_evaluation!
    raise_terminal('evaluation_not_accepted') unless evaluation.status == 'accepted'
  end

  def validate_incident!
    raise_terminal('incident_unavailable') unless incident.active_and_current?
    raise_terminal('notification_version_changed') unless snapshot_version == incident.notification_version
  end

  def validate_semantics!
    compatible = TechnicalIncidents::SemanticFilter.compatible?(incident, evaluation.classification)
    raise_terminal('semantic_compatibility_changed') unless compatible

    allowed = TechnicalIncidents::SemanticGate.allowed_match_source?(evaluation.classification, match_source)
    raise_terminal('semantic_gate_rejected') unless allowed
  end

  def snapshot_version
    snapshot = Array(evaluation.candidate_snapshot).find { |candidate| candidate['id'] == incident.id }
    snapshot&.fetch('notification_version', nil)
  end

  def match_source
    evaluation.match_source.presence || 'general'
  end

  def incident
    @incident ||= @delivery.technical_incident
  end

  def evaluation
    @evaluation ||= @delivery.technical_incident_evaluation
  end

  def raise_terminal(reason_code)
    raise TechnicalIncidents::OutboxProcessor::TerminalFailure, reason_code
  end

  def raise_disabled(reason_code)
    raise TechnicalIncidents::DeliveryAdapters::Base::DeliveryDisabled, reason_code
  end
end
