class Conversations::InactivityShadowClassifier
  Result = Struct.new(
    :classification, :reason_code, :operational_bucket, :session_generation,
    :customer_wait_seconds, :operation_wait_seconds, :confidence,
    keyword_init: true
  )

  def initialize(conversation, now: Time.current, message_snapshot: nil)
    @conversation = conversation
    @now = now
    @message_snapshot = message_snapshot
  end

  def call
    projection = Conversations::OperationalBucket.new(conversation).call
    classification, reason_code, confidence = classify(projection)

    Result.new(
      classification: classification,
      reason_code: reason_code,
      operational_bucket: projection.bucket,
      session_generation: session_generation,
      customer_wait_seconds: waiting_seconds(last_public_outgoing),
      operation_wait_seconds: waiting_seconds(last_public_incoming),
      confidence: confidence
    )
  end

  private

  attr_reader :conversation, :now, :message_snapshot

  def classify(projection)
    return %w[do_not_touch conversation_not_open] << 1.0 unless conversation.open?
    return %w[stale_inconsistent contradictory_operational_state] << 1.0 if projection.inconsistent
    return %w[operation_pending context_reset_pending] << 1.0 if context_reset_pending?
    return %w[operation_pending external_operation_pending] << 0.95 if operation_pending?
    return %w[handoff_pending awaiting_human] << 1.0 if projection.bucket == 'human_queue'
    return %w[waiting_human human_assigned] << 1.0 if projection.bucket == 'mine'
    return classify_bia if projection.bucket == 'bia'

    %w[unknown insufficient_safe_signals] << 0.25
  end

  def classify_bia
    return %w[waiting_automation latest_public_message_incoming] << 0.95 if last_public_message&.incoming?
    return %w[operation_pending outgoing_delivery_incomplete] << 0.95 if outgoing_delivery_pending?
    return %w[likely_completed completed_action_waiting_observation] << 0.85 if completed_action?
    return %w[waiting_customer latest_public_message_outgoing] << 0.9 if last_public_message&.outgoing?

    %w[unknown no_public_message] << 0.2
  end

  def context_reset_pending?
    attributes['bia_context_reset_required'] == true
  end

  def operation_pending?
    attributes['liberacao_ativa'] == true || attributes['operation_pending'] == true ||
      attributes['handoff_pending'] == true
  end

  def outgoing_delivery_pending?
    last_public_outgoing && !%w[sent delivered read].include?(last_public_outgoing.status)
  end

  def completed_action?
    attributes['bia_last_action_completed'] == true || attributes.dig('financeiro_state', 'delivered') == true
  end

  def last_public_message
    return message_snapshot[:last_public_message] if message_snapshot

    @last_public_message ||= conversation.messages.where(private: false).where.not(message_type: :activity).order(id: :desc).first
  end

  def last_public_incoming
    return message_snapshot[:last_public_incoming] if message_snapshot

    @last_public_incoming ||= conversation.messages.incoming.where(private: false).order(id: :desc).first
  end

  def last_public_outgoing
    return message_snapshot[:last_public_outgoing] if message_snapshot

    @last_public_outgoing ||= conversation.messages.outgoing.where(private: false).order(id: :desc).first
  end

  def waiting_seconds(message)
    return unless message

    [now.to_i - message.created_at.to_i, 0].max
  end

  def attributes
    @attributes ||= conversation.custom_attributes || {}
  end

  def session_generation
    Integer(attributes['bia_session_generation'] || 0).clamp(0, 2_147_483_647)
  rescue ArgumentError, TypeError
    0
  end
end
