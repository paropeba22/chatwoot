class TechnicalIncidents::LifecycleJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    activate_scheduled
    expire_active
    record_review_alerts
    record_forgotten_alerts
  end

  private

  def activate_scheduled
    TechnicalIncident.where(status: 'scheduled', archived_at: nil).where('starts_at <= ?', Time.current).find_each do |incident|
      next unless incident.account.feature_enabled?('technical_incidents')

      TechnicalIncidents::LifecycleService.new(incident: incident, actor: nil, origin: 'job')
                                            .transition!('active')
    rescue TechnicalIncidents::LifecycleService::InvalidTransition, ActiveRecord::RecordInvalid => e
      record_job_failure(incident, 'scheduled_activation_failed', e)
    end
  end

  def expire_active
    TechnicalIncident.where(status: 'active', archived_at: nil).where('expires_at <= ?', Time.current).find_each do |incident|
      next unless incident.account.feature_enabled?('technical_incidents')

      TechnicalIncidents::LifecycleService.new(incident: incident, actor: nil, origin: 'job')
                                            .transition!('expired')
    rescue TechnicalIncidents::LifecycleService::InvalidTransition, ActiveRecord::RecordInvalid => e
      record_job_failure(incident, 'expiration_failed', e)
    end
  end

  def record_review_alerts
    TechnicalIncident.where(status: %w[active monitoring], archived_at: nil).where('review_at <= ?', Time.current).find_each do |incident|
      next unless incident.account.feature_enabled?('technical_incidents')
      incident.with_lock do
        incident.reload
        next if incident.updates.where(action: 'review.due').where('created_at >= ?', incident.review_at).exists?

        TechnicalIncidents::AuditService.record!(
          incident: incident,
          action: 'review.due',
          origin: 'job',
          changeset: { review_at: incident.review_at, expires_at: incident.expires_at }
        )
      end
    end
  end

  def record_forgotten_alerts
    TechnicalIncident.where(status: 'active', archived_at: nil).where('updated_at <= ?', 2.hours.ago).find_each do |incident|
      next unless incident.account.feature_enabled?('technical_incidents')
      incident.with_lock do
        incident.reload
        next if incident.updates.where(action: 'incident.forgotten').where('created_at >= ?', 2.hours.ago).exists?

        TechnicalIncidents::AuditService.record!(
          incident: incident,
          action: 'incident.forgotten',
          origin: 'job',
          changeset: { last_updated_at: incident.updated_at, expires_at: incident.expires_at }
        )
      end
    end
  end

  def record_job_failure(incident, action, error)
    TechnicalIncidents::AuditService.record!(
      incident: incident,
      action: action,
      origin: 'job',
      changeset: { error_class: error.class.name }
    )
  end
end
