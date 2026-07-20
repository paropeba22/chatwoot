class TechnicalIncidents::OutboxProcessor
  class RetryableFailure < StandardError; end
  class TerminalFailure < StandardError; end
  class AwaitingDelivery < StandardError; end

  def initialize(delivery_id)
    @delivery_id = delivery_id
    @lock_token = SecureRandom.uuid
  end

  def call
    return unless TechnicalIncidents::Configuration.outbox_enabled?
    return unless claim!

    instrument_step('outbox.validate') { validate_current! }
    instrument_step('link') { ensure_link! }
    instrument_step('message.create') { ensure_message! }
    instrument_step('transport.enqueue') { ensure_transport! }
    instrument_step('label') { ensure_labels! }
    instrument_step('note') { ensure_note! }
    instrument_step('handoff') { ensure_handoff! }
    instrument_step('audit') { ensure_audit! }
    instrument_step('outbox.complete') { complete! }
  rescue AwaitingDelivery => e
    release_for_retry(e.message, count_attempt: true)
  rescue TechnicalIncidents::DeliveryAdapters::Base::DeliveryDisabled => e
    release_for_retry(e.message, count_attempt: false)
  rescue TechnicalIncidents::DeliveryAdapters::Base::UnsupportedInbox => e
    fail_terminal!("unsupported_inbox:#{e.message}")
  rescue TerminalFailure => e
    fail_terminal!(e.message)
  rescue StandardError => e
    release_for_retry(e.class.name, count_attempt: true)
  end

  private

  def claim!
    claimed = false
    delivery.with_lock do
      delivery.reload
      return false if delivery.outbox_state.in?(%w[completed failed_terminal])
      return false if delivery.outbox_state == 'processing' && delivery.locked_at.present? &&
                      delivery.locked_at > TechnicalIncidents::Configuration.outbox_lease.ago
      return false if delivery.next_retry_at.present? && delivery.next_retry_at > Time.current

      delivery.update!(
        outbox_state: 'processing',
        locked_at: Time.current,
        lock_token: @lock_token,
        last_error_code: nil
      )
      claimed = true
    end
    claimed
  end

  def validate_current!
    evaluation = delivery.technical_incident_evaluation
    incident = delivery.technical_incident
    raise TerminalFailure, 'feature_disabled' unless delivery.account.feature_enabled?('technical_incidents')
    unless TechnicalIncidents::Configuration.automation_mode == 'active'
      raise TechnicalIncidents::DeliveryAdapters::Base::DeliveryDisabled, 'server_automation_not_active'
    end
    unless TechnicalIncidents::Configuration.delivery_enabled?
      raise TechnicalIncidents::DeliveryAdapters::Base::DeliveryDisabled, 'delivery_disabled'
    end
    raise TerminalFailure, 'account_mismatch' unless account_consistent?
    raise TerminalFailure, 'evaluation_not_accepted' unless evaluation.status == 'accepted'
    raise TerminalFailure, 'incident_unavailable' unless incident.active_and_current?
    snapshot = Array(evaluation.candidate_snapshot).find { |candidate| candidate['id'] == incident.id }
    raise TerminalFailure, 'notification_version_changed' unless snapshot&.fetch('notification_version', nil) == incident.notification_version
    raise TerminalFailure, 'semantic_compatibility_changed' unless TechnicalIncidents::SemanticFilter.compatible?(incident, evaluation.classification)

    match_source = evaluation.match_source.presence || 'general'
    unless TechnicalIncidents::SemanticGate.allowed_match_source?(evaluation.classification, match_source)
      raise TerminalFailure, 'semantic_gate_rejected'
    end
  end

  def account_consistent?
    delivery.account_id == delivery.technical_incident.account_id &&
      delivery.account_id == delivery.technical_incident_evaluation.account_id &&
      delivery.account_id == delivery.conversation.account_id
  end

  def ensure_link!
    return if delivery.link_state == 'completed'

    evaluation = delivery.technical_incident_evaluation
    link = delivery.account.technical_incident_conversation_links.find_or_create_by!(
      technical_incident: delivery.technical_incident,
      conversation: delivery.conversation,
      contract_reference: evaluation.selected_contract['contract_id'].to_s,
      notification_version: delivery.technical_incident.notification_version
    ) { |record| record.technical_incident_evaluation = evaluation }
    update_delivery!(technical_incident_conversation_link: link, link_state: 'completed')
  end

  def ensure_message!
    return if delivery.message_state.in?(%w[not_required created])

    message = adapter.create_message!
    update_delivery!(
      message: message,
      message_state: 'created',
      state: 'message_created',
      provider: 'api_inbox_webhook',
      provider_reference: "technical-incident-#{delivery.id}"
    )
  rescue StandardError
    update_delivery!(message_state: 'failed_retryable')
    raise
  end

  def ensure_transport!
    return if delivery.transport_state == 'not_required'
    return if delivery.transport_state == 'delivered'

    message = delivery.message
    raise RetryableFailure, 'message_missing' unless message
    message.reload
    if message.delivered? || message.read?
      update_delivery!(transport_state: 'delivered', state: 'delivered', delivered_at: Time.current)
      return
    end
    if message.failed?
      update_delivery!(transport_state: 'failed_retryable')
    end
    if delivery.transport_state.in?(%w[pending failed_retryable])
      message.update!(status: :sent, external_error: nil) if message.failed?
      provider = adapter.enqueue_transport!(message)
      update_delivery!(
        transport_state: 'queued',
        state: 'delivery_queued',
        provider: provider,
        delivery_queued_at: Time.current
      )
    end

    message.reload
    if message.delivered? || message.read?
      update_delivery!(transport_state: 'delivered', state: 'delivered', delivered_at: Time.current)
      return
    end
    if message.failed?
      update_delivery!(transport_state: 'failed_retryable')
      raise RetryableFailure, 'transport_failed'
    end

    raise AwaitingDelivery, 'awaiting_transport_confirmation'
  end

  def ensure_labels!
    return if delivery.label_state == 'not_required'
    return if delivery.label_state == 'completed'

    labels = delivery.conversation.label_list - ['bot-bia']
    labels |= ['aguardando-humano', "incidente-tecnico-#{delivery.technical_incident_id}"]
    delivery.conversation.update_labels(labels)
    update_delivery!(label_state: 'completed')
  rescue StandardError
    update_delivery!(label_state: 'failed_retryable')
    raise
  end

  def ensure_note!
    return if delivery.note_state == 'not_required'
    return if delivery.note_state == 'completed'

    existing = delivery.conversation.messages
                       .where(private: true)
                       .where("content_attributes ->> 'technical_incident_delivery_id' = ?", delivery.id.to_s)
                       .first
    existing ||= delivery.conversation.messages.create!(
      account: delivery.account,
      inbox: delivery.conversation.inbox,
      message_type: :outgoing,
      private: true,
      sender: nil,
      content: "Incidente técnico ##{delivery.technical_incident_id} vinculado automaticamente.",
      content_attributes: {
        technical_incident_delivery_id: delivery.id,
        technical_incident_outbox_managed: true,
        technical_incident_private_note: true
      }
    )
    update_delivery!(note_state: 'completed') if existing
  rescue StandardError
    update_delivery!(note_state: 'failed_retryable')
    raise
  end

  def ensure_handoff!
    return if delivery.handoff_state == 'not_required'
    return if delivery.handoff_state == 'completed'

    conversation = delivery.conversation
    conversation.update!(assignee_agent_bot_id: nil) if conversation.assignee_agent_bot_id.present?
    conversation.bot_handoff!
    update_delivery!(
      handoff_state: 'completed',
      state: 'handoff_completed',
      handoff_completed_at: Time.current
    )
  rescue StandardError
    update_delivery!(handoff_state: 'failed_retryable')
    raise
  end

  def ensure_audit!
    return if delivery.audit_state == 'completed'

    evaluation = delivery.technical_incident_evaluation
    existing = delivery.technical_incident.updates.find_by(
      action: 'commit.completed',
      request_id: evaluation.request_id
    )
    existing ||= TechnicalIncidents::AuditService.record!(
      incident: delivery.technical_incident,
      action: 'commit.completed',
      actor: evaluation.agent_bot,
      origin: 'automation',
      request_id: evaluation.request_id,
      changeset: {
        conversation_id: delivery.conversation_id,
        delivery_id: delivery.id,
        message_id: delivery.message_id,
        match_source: evaluation.match_source
      }
    )
    update_delivery!(audit_state: 'completed') if existing
  rescue StandardError
    update_delivery!(audit_state: 'failed_retryable')
    raise
  end

  def complete!
    update_delivery!(
      outbox_state: 'completed',
      state: delivery.handoff_state == 'completed' ? 'handoff_completed' : 'delivered',
      completed_at: Time.current,
      locked_at: nil,
      lock_token: nil,
      next_retry_at: nil,
      last_error: nil,
      last_error_code: nil
    )
  end

  def release_for_retry(reason_code, count_attempt:)
    return unless @delivery

    @delivery.with_lock do
      @delivery.reload
      return unless @delivery.lock_token == @lock_token

      attempts = @delivery.attempts + (count_attempt ? 1 : 0)
      terminal = attempts >= TechnicalIncidents::Configuration.max_delivery_attempts
      @delivery.update!(
        outbox_state: terminal ? 'failed_terminal' : 'retry',
        attempts: attempts,
        next_retry_at: terminal ? nil : retry_at(attempts),
        locked_at: nil,
        lock_token: nil,
        completed_at: terminal ? Time.current : nil,
        last_error: reason_code.to_s.first(500),
        last_error_code: reason_code.to_s.first(100)
      )
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def fail_terminal!(reason_code)
    return unless @delivery

    @delivery.with_lock do
      @delivery.update!(
        outbox_state: 'failed_terminal',
        completed_at: Time.current,
        locked_at: nil,
        lock_token: nil,
        next_retry_at: nil,
        last_error: reason_code.to_s.first(500),
        last_error_code: reason_code.to_s.first(100)
      )
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def retry_at(attempts)
    [2**[attempts, 8].min, 300].min.minutes.from_now
  end

  def instrument_step(event, &block)
    TechnicalIncidents::Instrumentation.measure(
      event,
      delivery_id: delivery.id,
      outbox_id: delivery.id,
      incident_id: delivery.technical_incident_id,
      conversation_id: delivery.conversation_id,
      evaluation_id: delivery.technical_incident_evaluation.opaque_id,
      attempt: delivery.attempts,
      &block
    )
  end

  def update_delivery!(attributes)
    delivery.with_lock do
      delivery.reload
      raise RetryableFailure, 'outbox_lease_lost' unless delivery.lock_token == @lock_token

      delivery.update!(attributes)
    end
  end

  def delivery
    @delivery ||= TechnicalIncidentDelivery.includes(
      :account, :technical_incident, :technical_incident_evaluation, conversation: { inbox: :channel }
    ).find(@delivery_id)
  end

  def adapter
    @adapter ||= TechnicalIncidents::DeliveryAdapters.for(delivery)
  end
end
