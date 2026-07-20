class TechnicalIncidents::OutboxProcessor
  class RetryableFailure < StandardError; end
  class TerminalFailure < StandardError; end
  class AwaitingDelivery < StandardError; end

  def initialize(delivery_or_id)
    @delivery = delivery_or_id if delivery_or_id.is_a?(TechnicalIncidentDelivery)
    @delivery_id = delivery_or_id.respond_to?(:id) ? delivery_or_id.id : delivery_or_id
    @lock_token = SecureRandom.uuid
  end

  def call
    return unless TechnicalIncidents::Configuration.outbox_enabled?
    return unless lease.claim!

    process_delivery
  rescue AwaitingDelivery => e
    lease.release_for_retry(e.message, count_attempt: true)
  rescue TechnicalIncidents::DeliveryAdapters::Base::DeliveryDisabled => e
    lease.release_for_retry(e.message, count_attempt: false)
  rescue TechnicalIncidents::DeliveryAdapters::Base::UnsupportedInbox => e
    lease.fail_terminal!("unsupported_inbox:#{e.message}")
  rescue TerminalFailure => e
    lease.fail_terminal!(e.message)
  rescue StandardError => e
    lease.release_for_retry(e.class.name, count_attempt: true)
  end

  private

  def process_delivery
    instrument_step('outbox.validate') { validator.validate! }
    instrument_step('link') { writer.ensure_link! }
    instrument_step('message.create') { writer.ensure_message! }
    instrument_step('transport.enqueue') { transport.ensure_delivered! }
    instrument_step('label') { writer.ensure_labels! }
    instrument_step('note') { writer.ensure_note! }
    instrument_step('handoff') { writer.ensure_handoff! }
    instrument_step('audit') { writer.ensure_audit! }
    instrument_step('outbox.complete') { lease.complete! }
  end

  def instrument_step(event, &)
    TechnicalIncidents::Instrumentation.measure(event, instrumentation_context, &)
  end

  def instrumentation_context
    {
      delivery_id: delivery.id,
      outbox_id: delivery.id,
      incident_id: delivery.technical_incident_id,
      conversation_id: delivery.conversation_id,
      evaluation_id: delivery.technical_incident_evaluation.opaque_id,
      attempt: delivery.attempts
    }
  end

  def delivery
    @delivery ||= TechnicalIncidentDelivery.includes(
      :account, :technical_incident, :technical_incident_evaluation, conversation: { inbox: :channel }
    ).find(@delivery_id)
  end

  def lease
    @lease ||= TechnicalIncidents::OutboxLease.new(delivery: delivery, lock_token: @lock_token)
  end

  def validator
    @validator ||= TechnicalIncidents::OutboxValidator.new(delivery)
  end

  def adapter
    @adapter ||= TechnicalIncidents::DeliveryAdapters.for(delivery)
  end

  def writer
    @writer ||= TechnicalIncidents::OutboxConversationWriter.new(delivery: delivery, lease: lease, adapter: adapter)
  end

  def transport
    @transport ||= TechnicalIncidents::OutboxTransport.new(delivery: delivery, lease: lease, adapter: adapter)
  end
end
