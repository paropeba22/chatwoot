class TechnicalIncident < ApplicationRecord
  INCIDENT_TYPES = %w[unplanned_outage degradation scheduled_maintenance external_provider company_application other].freeze
  STATUSES = %w[draft scheduled active monitoring resolved expired cancelled].freeze
  SEVERITIES = %w[informational minor major critical].freeze
  PROBLEM_TYPES = %w[
    internet_connectivity physical_fiber optical_alarm dns external_service company_application
    iptv telephony other unidentified
  ].freeze
  SERVICE_KEYS = %w[internet dns google youtube grupo_telecom_app iptv telephony other].freeze
  ACTIONS = %w[message_and_handoff message_only handoff_only].freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  belongs_to :resolved_by, class_name: 'User', optional: true

  has_many :scope_groups, -> { order(:position, :id) },
           class_name: 'TechnicalIncidentScopeGroup', dependent: :destroy, inverse_of: :technical_incident
  has_many :updates, class_name: 'TechnicalIncidentUpdate', dependent: :restrict_with_error
  has_many :evaluations, class_name: 'TechnicalIncidentEvaluation', dependent: :restrict_with_error
  has_many :conversation_links, class_name: 'TechnicalIncidentConversationLink', dependent: :restrict_with_error
  has_many :conversations, through: :conversation_links
  has_many :deliveries, class_name: 'TechnicalIncidentDelivery', dependent: :restrict_with_error

  accepts_nested_attributes_for :scope_groups, allow_destroy: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :incident_type, inclusion: { in: INCIDENT_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :priority, inclusion: { in: 0..100 }
  validates :problem_types, presence: true
  validates :action, inclusion: { in: ACTIONS }
  validates :customer_message, length: { maximum: 4_000 }, allow_blank: true
  validates :internal_note, length: { maximum: 10_000 }, allow_blank: true
  validate :controlled_taxonomy_values
  validate :account_consistency
  validate :valid_duration

  scope :not_archived, -> { where(archived_at: nil) }
  scope :intercepting, lambda {
    now = Time.current
    where(status: 'active', archived_at: nil)
      .where('starts_at IS NULL OR starts_at <= ?', now)
      .where('expires_at > ?', now)
  }

  before_validation :sanitize_text_fields

  def active_and_current?
    status == 'active' && archived_at.nil? && (starts_at.nil? || starts_at <= Time.current) && expires_at.present? && expires_at > Time.current
  end

  def deletable_draft?
    status == 'draft' &&
      updates.where.not(action: %w[incident.created incident.updated]).none? &&
      evaluations.none? &&
      conversation_links.none? &&
      deliveries.none?
  end

  def general_scope?
    scope_groups.any? do |group|
      types = group.criteria.map(&:criterion_type)
      types.any? && (types - %w[general service_specific]).empty?
    end
  end

  def service_specific_scope?
    scope_groups.any? { |group| group.criteria.any?(&:service_specific?) }
  end

  def customer_visible_snapshot
    {
      id: id,
      title: title,
      status: status,
      severity: severity,
      priority: priority,
      problem_types: problem_types,
      affected_services: affected_services,
      notification_version: notification_version,
      estimated_resolution_at: estimated_resolution_at,
      expires_at: expires_at
    }
  end

  private

  def sanitize_text_fields
    self.title = TechnicalIncidents::TextSanitizer.call(title)
    self.customer_message = TechnicalIncidents::TextSanitizer.call(customer_message)
    self.internal_note = TechnicalIncidents::TextSanitizer.call(internal_note)
  end

  def valid_duration
    return if expires_at.blank?

    base_time = starts_at || Time.current
    errors.add(:expires_at, :after_start) if expires_at <= base_time
    errors.add(:expires_at, :too_far) if expires_at > base_time + 7.days
  end

  def account_consistency
    scope_groups.each do |group|
      errors.add(:scope_groups, :invalid) if group.account_id.present? && group.account_id != account_id
    end
  end

  def controlled_taxonomy_values
    unless problem_types.is_a?(Array) && problem_types.all? { |value| PROBLEM_TYPES.include?(value) }
      errors.add(:problem_types, :inclusion)
    end
    return if affected_services.is_a?(Array) && affected_services.all? { |value| SERVICE_KEYS.include?(value) }

    errors.add(:affected_services, :inclusion)
  end
end
