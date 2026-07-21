class TechnicalIncidents::OutboxTransport
  def initialize(delivery:, lease:, adapter:)
    @delivery = delivery
    @lease = lease
    @adapter = adapter
  end

  def ensure_delivered!
    return if transport_complete?

    message = required_message
    return mark_delivered! if delivered?(message)

    prepare_retry!(message)
    enqueue!(message) if transport_pending?
    confirm!(message)
  end

  private

  def transport_complete?
    @delivery.transport_state.in?(%w[not_required delivered])
  end

  def required_message
    @delivery.message || raise(TechnicalIncidents::OutboxProcessor::RetryableFailure, 'message_missing')
  end

  def prepare_retry!(message)
    return unless message.failed?

    @lease.update!(transport_state: 'failed_retryable')
    message.update!(status: :sent, external_error: nil)
  end

  def enqueue!(message)
    provider = @adapter.enqueue_transport!(message)
    @lease.update!(
      transport_state: 'queued',
      state: 'delivery_queued',
      provider: provider,
      delivery_queued_at: Time.current
    )
  end

  def confirm!(message)
    message.reload
    return mark_delivered! if delivered?(message)

    mark_transport_failure! if message.failed?
    raise TechnicalIncidents::OutboxProcessor::AwaitingDelivery, 'awaiting_transport_confirmation'
  end

  def mark_transport_failure!
    @lease.update!(transport_state: 'failed_retryable')
    raise TechnicalIncidents::OutboxProcessor::RetryableFailure, 'transport_failed'
  end

  def mark_delivered!
    @lease.update!(transport_state: 'delivered', state: 'delivered', delivered_at: Time.current)
  end

  def delivered?(message)
    message.reload
    message.delivered? || message.read?
  end

  def transport_pending?
    @delivery.reload.transport_state.in?(%w[pending failed_retryable])
  end
end
