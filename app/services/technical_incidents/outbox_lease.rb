class TechnicalIncidents::OutboxLease
  def initialize(delivery:, lock_token:)
    @delivery = delivery
    @lock_token = lock_token
  end

  def claim!
    claimed = false
    @delivery.with_lock do
      @delivery.reload
      claimed = claimable?
      reserve! if claimed
    end
    claimed
  end

  def update!(attributes)
    @delivery.with_lock do
      @delivery.reload
      ensure_owned!
      @delivery.update!(attributes)
    end
  end

  def complete!
    update!(
      outbox_state: 'completed',
      state: completion_state,
      completed_at: Time.current,
      locked_at: nil,
      lock_token: nil,
      next_retry_at: nil,
      last_error: nil,
      last_error_code: nil
    )
  end

  def release_for_retry(reason_code, count_attempt:)
    @delivery.with_lock do
      @delivery.reload
      release_owned_lease(reason_code, count_attempt) if owned?
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def fail_terminal!(reason_code)
    @delivery.with_lock do
      @delivery.reload
      mark_terminal(reason_code) if owned?
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  private

  def claimable?
    return false if @delivery.outbox_state.in?(%w[completed failed_terminal])
    return false if active_lease?

    @delivery.next_retry_at.blank? || @delivery.next_retry_at <= Time.current
  end

  def active_lease?
    @delivery.outbox_state == 'processing' &&
      @delivery.locked_at.present? &&
      @delivery.locked_at > TechnicalIncidents::Configuration.outbox_lease.ago
  end

  def reserve!
    @delivery.update!(
      outbox_state: 'processing',
      locked_at: Time.current,
      lock_token: @lock_token,
      last_error_code: nil
    )
  end

  def release_owned_lease(reason_code, count_attempt)
    attempts = @delivery.attempts + (count_attempt ? 1 : 0)
    terminal = attempts >= TechnicalIncidents::Configuration.max_delivery_attempts
    @delivery.update!(retry_attributes(reason_code, attempts, terminal))
  end

  def retry_attributes(reason_code, attempts, terminal)
    {
      outbox_state: terminal ? 'failed_terminal' : 'retry',
      attempts: attempts,
      next_retry_at: terminal ? nil : retry_at(attempts),
      locked_at: nil,
      lock_token: nil,
      completed_at: terminal ? Time.current : nil,
      last_error: reason_code.to_s.first(500),
      last_error_code: reason_code.to_s.first(100)
    }
  end

  def mark_terminal(reason_code)
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

  def retry_at(attempts)
    [2**[attempts, 8].min, 300].min.minutes.from_now
  end

  def completion_state
    @delivery.handoff_state == 'completed' ? 'handoff_completed' : 'delivered'
  end

  def ensure_owned!
    raise TechnicalIncidents::OutboxProcessor::RetryableFailure, 'outbox_lease_lost' unless owned?
  end

  def owned?
    @delivery.lock_token == @lock_token
  end
end
