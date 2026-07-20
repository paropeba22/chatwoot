module TechnicalIncidentAutomationSecurity
  extend ActiveSupport::Concern

  private

  def ensure_technical_incident_https!
    return unless Rails.env.production?
    return if request.ssl?

    render json: { error: 'https_required' }, status: :upgrade_required
  end

  def enforce_technical_incident_account_rate_limit!
    endpoint = "#{controller_path}:#{action_name}"
    period = Time.current.to_i / 60
    key = "technical-incidents:rate:account:#{Current.account.id}:#{endpoint}:#{period}"
    count = Rails.cache.increment(key, 1, expires_in: 2.minutes)
    unless count
      Rails.cache.write(key, 1, expires_in: 2.minutes)
      count = 1
    end
    limit = ENV.fetch('RATE_LIMIT_TECHNICAL_INCIDENTS_ACCOUNT', '300').to_i.clamp(1, 10_000)
    render json: { error: 'rate_limit_exceeded' }, status: :too_many_requests if count > limit
  rescue StandardError => e
    TechnicalIncidents::Instrumentation.record(
      event: 'rate_limit.unavailable',
      reason_code: e.class.name
    )
    render json: { error: 'rate_limit_unavailable' }, status: :service_unavailable
  end
end
