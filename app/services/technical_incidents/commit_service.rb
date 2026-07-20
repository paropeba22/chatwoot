class TechnicalIncidents::CommitService
  class StaleEvaluation < StandardError; end

  def initialize(account:, opaque_id:)
    @account = account
    @opaque_id = opaque_id
  end

  def call
    return blocked_response('server_automation_not_active') unless TechnicalIncidents::Configuration.automation_mode == 'active'
    return blocked_response('outbox_disabled') unless TechnicalIncidents::Configuration.outbox_enabled?

    delivery = nil
    duplicate_response = nil
    idempotency_key_value = nil
    ActiveRecord::Base.transaction do
      evaluation = @account.technical_incident_evaluations.lock.find_by!(opaque_id: @opaque_id)
      incident = @account.technical_incidents.lock.find_by(id: evaluation.technical_incident_id)
      if evaluation.status == 'accepted'
        existing = @account.technical_incident_deliveries.find_by(technical_incident_evaluation: evaluation)
        raise StaleEvaluation, 'accepted_delivery_missing' unless existing

        duplicate_response = response(existing, 'duplicate', 'idempotency_key_exists')
        next
      end

      validate!(evaluation, incident)
      idempotency_key_value = idempotency_key(evaluation, incident)
      existing = @account.technical_incident_deliveries.find_by(idempotency_key: idempotency_key_value)
      if existing
        duplicate_response = response(existing, 'duplicate', 'idempotency_key_exists')
        next
      end

      delivery = reserve_delivery!(evaluation, incident, idempotency_key_value)
      evaluation.update!(status: 'accepted', committed_at: Time.current)
    end
    return duplicate_response if duplicate_response

    TechnicalIncidents::Instrumentation.record(
      event: 'commit.reserved',
      request_id: delivery.technical_incident_evaluation.request_id,
      evaluation_id: delivery.technical_incident_evaluation.opaque_id,
      incident_id: delivery.technical_incident_id,
      conversation_id: delivery.conversation_id,
      delivery_id: delivery.id,
      outbox_id: delivery.id,
      status: delivery.outbox_state
    )
    enqueue_dispatcher
    response(delivery, 'accepted', 'outbox_reserved')
  rescue ActiveRecord::RecordNotFound
    blocked_response('evaluation_not_found')
  rescue StaleEvaluation => e
    blocked_response(e.message)
  rescue ActiveRecord::RecordNotUnique
    existing = @account.technical_incident_deliveries.find_by(idempotency_key: idempotency_key_value)
    response(existing, 'duplicate', 'concurrent_commit')
  end

  private

  def validate!(evaluation, incident)
    raise StaleEvaluation, 'feature_disabled' unless @account.feature_enabled?('technical_incidents')
    raise StaleEvaluation, 'server_automation_not_active' unless TechnicalIncidents::Configuration.automation_mode == 'active'
    raise StaleEvaluation, 'outbox_disabled' unless TechnicalIncidents::Configuration.outbox_enabled?
    raise StaleEvaluation, 'evaluation_not_active_mode' unless evaluation.mode == 'active'
    raise StaleEvaluation, 'evaluation_expired' if evaluation.stale?
    raise StaleEvaluation, 'evaluation_not_matched' unless evaluation.status.in?(%w[general_match matched])
    raise StaleEvaluation, 'incident_unavailable' unless incident&.active_and_current?
    raise StaleEvaluation, 'account_mismatch' unless evaluation.account_id == @account.id && incident.account_id == @account.id
    raise StaleEvaluation, 'notification_version_changed' unless snapshot_version(evaluation) == incident.notification_version
    raise StaleEvaluation, 'conversation_unavailable' unless evaluation.conversation.account_id == @account.id
    raise StaleEvaluation, 'automation_actor_missing' unless evaluation.agent_bot
    unless evaluation.agent_bot.account_id == @account.id && evaluation.agent_bot.bot_config.to_h['technical_incidents_api'] == true
      raise StaleEvaluation, 'automation_actor_invalid'
    end
    raise StaleEvaluation, 'selected_contract_missing' if evaluation.status == 'matched' && evaluation.selected_contract['contract_id'].blank?
    raise StaleEvaluation, 'semantic_compatibility_changed' unless TechnicalIncidents::SemanticFilter.compatible?(incident, evaluation.classification)

    match_source = evaluation.status == 'general_match' ? 'general' : evaluation.match_source
    unless TechnicalIncidents::SemanticGate.allowed_match_source?(evaluation.classification, match_source)
      raise StaleEvaluation, 'semantic_gate_rejected'
    end

    TechnicalIncidents::IncidentValidator.new(incident).validate!
    revalidate_scope!(evaluation, incident)
  end

  def revalidate_scope!(evaluation, incident)
    if evaluation.status == 'general_match'
      raise StaleEvaluation, 'general_scope_changed' unless incident.general_scope?
      return
    end

    match = TechnicalIncidents::Matcher.new(
      incident: incident,
      contract: evaluation.selected_contract,
      classification: evaluation.classification
    ).call
    raise StaleEvaluation, 'deterministic_match_changed' unless match
    raise StaleEvaluation, 'match_source_changed' unless match[:match_source] == evaluation.match_source
  end

  def snapshot_version(evaluation)
    snapshot = Array(evaluation.candidate_snapshot).find { |candidate| candidate['id'] == evaluation.technical_incident_id }
    snapshot&.fetch('notification_version', nil)
  end

  def idempotency_key(evaluation, incident)
    [
      evaluation.conversation_id,
      incident.id,
      incident.notification_version,
      delivery_kind(incident)
    ].join(':')
  end

  def delivery_kind(incident)
    return 'initial' if incident.notification_version == 1

    reopening = incident.updates
                        .where(action: %w[transition.resolved.active transition.expired.active transition.cancelled.active])
                        .order(id: :desc)
                        .find do |update|
      Array(update.changeset['notification_version']).last == incident.notification_version
    end
    reopening ? 'reopening' : 'update'
  end

  def reserve_delivery!(evaluation, incident, key)
    message_required = incident.action != 'handoff_only'
    handoff_required = incident.action != 'message_only'
    @account.technical_incident_deliveries.create!(
      technical_incident: incident,
      technical_incident_evaluation: evaluation,
      conversation: evaluation.conversation,
      idempotency_key: key,
      delivery_kind: delivery_kind(incident),
      state: 'reserved',
      outbox_state: 'pending',
      message_state: message_required ? 'pending' : 'not_required',
      transport_state: message_required ? 'pending' : 'not_required',
      link_state: 'pending',
      label_state: handoff_required ? 'pending' : 'not_required',
      note_state: handoff_required ? 'pending' : 'not_required',
      handoff_state: handoff_required ? 'pending' : 'not_required',
      audit_state: 'pending',
      next_retry_at: Time.current
    )
  end

  def enqueue_dispatcher
    TechnicalIncidents::OutboxDispatchJob.perform_later
  rescue StandardError => e
    TechnicalIncidents::Instrumentation.record(
      event: 'outbox.enqueue_failed',
      delivery_id: nil,
      reason_code: e.class.name
    )
  end

  def blocked_response(reason_code)
    TechnicalIncidents::Instrumentation.record(
      event: 'commit.blocked',
      status: 'stale',
      reason_code: reason_code
    )
    {
      contract_version: TechnicalIncidents::PrecheckService::CONTRACT_VERSION,
      status: 'stale',
      reason_code: reason_code
    }
  end

  def response(delivery, status, reason_code)
    {
      contract_version: TechnicalIncidents::PrecheckService::CONTRACT_VERSION,
      status: status,
      reason_code: reason_code,
      delivery_id: delivery&.id,
      delivery_state: delivery&.outbox_state,
      message_id: delivery&.message_id
    }.compact
  end
end
