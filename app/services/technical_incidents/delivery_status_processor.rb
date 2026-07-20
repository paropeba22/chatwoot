class TechnicalIncidents::DeliveryStatusProcessor
  def initialize(delivery)
    @delivery = delivery
  end

  def call
    return unless @delivery.message

    @delivery.with_lock do
      @delivery.reload
      update_transport_state
    end
  end

  private

  def update_transport_state
    if @delivery.message.failed?
      mark_failed
    elsif @delivery.message.delivered? || @delivery.message.read?
      mark_delivered
    end
  end

  def mark_failed
    @delivery.update!(
      transport_state: 'failed_retryable',
      outbox_state: 'retry',
      next_retry_at: Time.current,
      last_error_code: 'transport_failed',
      last_error: @delivery.message.content_attributes['external_error'].to_s.first(500)
    )
  end

  def mark_delivered
    @delivery.update!(
      transport_state: 'delivered',
      state: 'delivered',
      delivered_at: Time.current,
      outbox_state: 'retry',
      next_retry_at: Time.current
    )
  end
end
