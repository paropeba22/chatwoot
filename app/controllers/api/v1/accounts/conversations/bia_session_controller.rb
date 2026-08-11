class Api::V1::Accounts::Conversations::BiaSessionController < Api::V1::Accounts::Conversations::BaseController
  def reset_context
    render_result(reset_service.call)
  rescue Conversations::BiaSession::ResetContextService::Conflict => e
    render_conflict(e)
  rescue Conversations::BiaSession::ResetContextService::FeatureDisabled
    render json: { error: 'feature_disabled' }, status: :not_found
  rescue Conversations::BiaSession::ResetContextService::InvalidRequest => e
    render json: { error: 'invalid_bia_session_operation', reason_code: e.reason_code }, status: :unprocessable_entity
  end

  def create_message
    render_result(message_service.call)
  rescue Conversations::BiaSession::CreateMessageService::Conflict => e
    render_conflict(e)
  rescue Conversations::BiaSession::CreateMessageService::FeatureDisabled
    render json: { error: 'feature_disabled' }, status: :not_found
  rescue Conversations::BiaSession::CreateMessageService::InvalidRequest => e
    render json: { error: 'invalid_bia_session_operation', reason_code: e.reason_code }, status: :unprocessable_entity
  end

  private

  def reset_service
    Conversations::BiaSession::ResetContextService.new(**service_arguments, attributes: operation_params)
  end

  def message_service
    Conversations::BiaSession::CreateMessageService.new(**service_arguments, attributes: operation_params)
  end

  def service_arguments
    {
      account: Current.account,
      actor: Current.user || @resource,
      account_user: Current.account_user,
      conversation_display_id: params[:conversation_id]
    }
  end

  def operation_params
    params.permit(
      :expected_generation, :source_message_id, :idempotency_key, :reset_profile,
      :content, :content_type, :private
    )
  end

  def render_result(result)
    render json: {
      status: result.status,
      reason_code: result.reason_code,
      operation_id: result.operation&.id,
      message_id: result.respond_to?(:message) ? result.message&.id : nil,
      session: session_snapshot(result.conversation)
    }.compact
  end

  def render_conflict(error)
    render json: {
      error: 'bia_session_conflict',
      reason_code: error.reason_code,
      session: session_snapshot(error.conversation.reload)
    }, status: :conflict
  end

  def session_snapshot(conversation)
    Conversations::BiaSession::SessionValidator.new(
      conversation: conversation,
      expected_generation: 0,
      source_message_id: 0
    ).snapshot
  end
end
