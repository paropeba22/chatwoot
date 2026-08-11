class Api::V1::Accounts::ConversationInactivityShadowsController < Api::V1::Accounts::BaseController
  AGGREGATE_COLUMNS = [
    :classification,
    :operational_bucket,
    :reason_code,
    'COUNT(*) AS assessment_count',
    'MAX(customer_wait_seconds) AS max_customer_wait_seconds',
    'MAX(operation_wait_seconds) AS max_operation_wait_seconds',
    'AVG(confidence) AS average_confidence'
  ].freeze

  before_action :ensure_feature_enabled
  before_action :ensure_administrator

  def show
    assessments = Current.account.conversation_inactivity_shadow_assessments
    render json: {
      generated_at: Time.current,
      total: assessments.count,
      groups: grouped_assessments(assessments)
    }
  end

  private

  def grouped_assessments(assessments)
    assessments
      .select(*AGGREGATE_COLUMNS)
      .group(:classification, :operational_bucket, :reason_code)
      .map { |group| group_payload(group) }
  end

  def group_payload(group)
    {
      classification: group.classification,
      operational_bucket: group.operational_bucket,
      reason_code: group.reason_code,
      count: group.assessment_count.to_i,
      max_customer_wait_seconds: group.max_customer_wait_seconds&.to_i,
      max_operation_wait_seconds: group.max_operation_wait_seconds&.to_i,
      average_confidence: group.average_confidence&.to_f
    }
  end

  def ensure_feature_enabled
    head :not_found unless Current.account.feature_enabled?('conversation_inactivity_shadow')
  end

  def ensure_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end
end
