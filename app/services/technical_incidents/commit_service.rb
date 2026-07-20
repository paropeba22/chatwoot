class TechnicalIncidents::CommitService
  class StaleEvaluation < StandardError; end
  Result = Struct.new(:delivery, :status, :reason_code, keyword_init: true)

  def initialize(account:, opaque_id:)
    @account = account
    @opaque_id = opaque_id
  end

  def call
    return blocked_response('server_automation_not_active') unless TechnicalIncidents::Configuration.automation_mode == 'active'
    return blocked_response('outbox_disabled') unless TechnicalIncidents::Configuration.outbox_enabled?

    result = reserve
    return response(result.delivery, result.status, result.reason_code) if result.status == 'duplicate'

    record_reservation(result.delivery)
    enqueue_dispatcher
    response(result.delivery, result.status, result.reason_code)
  rescue ActiveRecord::RecordNotFound
    blocked_response('evaluation_not_found')
  rescue StaleEvaluation => e
    blocked_response(e.message)
  rescue ActiveRecord::RecordNotUnique
    existing = @account.technical_incident_deliveries.find_by(idempotency_key: @idempotency_key)
    response(existing, 'duplicate', 'concurrent_commit')
  end

  private

  def reserve
    ActiveRecord::Base.transaction { reserve_locked }
  end

  def reserve_locked
    evaluation = @account.technical_incident_evaluations.lock.find_by!(opaque_id: @opaque_id)
    incident = @account.technical_incidents.lock.find_by(id: evaluation.technical_incident_id)
    duplicate = accepted_delivery(evaluation)
    return duplicate_result(duplicate) if duplicate

    TechnicalIncidents::CommitValidator.new(account: @account, evaluation: evaluation, incident: incident).validate!
    @idempotency_key = idempotency_key(evaluation, incident)
    existing = @account.technical_incident_deliveries.find_by(idempotency_key: @idempotency_key)
    return duplicate_result(existing) if existing

    delivery = reserve_delivery!(evaluation, incident, @idempotency_key)
    evaluation.update!(status: 'accepted', committed_at: Time.current)
    Result.new(delivery: delivery, status: 'accepted', reason_code: 'outbox_reserved')
  end

  def accepted_delivery(evaluation)
    return unless evaluation.status == 'accepted'

    existing = @account.technical_incident_deliveries.find_by(technical_incident_evaluation: evaluation)
    raise StaleEvaluation, 'accepted_delivery_missing' unless existing

    existing
  end

  def duplicate_result(delivery)
    Result.new(delivery: delivery, status: 'duplicate', reason_code: 'idempotency_key_exists')
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

  def record_reservation(delivery)
    evaluation = delivery.technical_incident_evaluation
    TechnicalIncidents::Instrumentation.record(
      event: 'commit.reserved',
      request_id: evaluation.request_id,
      evaluation_id: evaluation.opaque_id,
      incident_id: delivery.technical_incident_id,
      conversation_id: delivery.conversation_id,
      delivery_id: delivery.id,
      outbox_id: delivery.id,
      status: delivery.outbox_state
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
