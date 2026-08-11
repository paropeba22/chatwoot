class Api::V1::Accounts::Conversations::AutomationTransitionsController < Api::V1::Accounts::BaseController
  def create
    result = transition_service.call
    @conversation = result.conversation.reload
    @transition = result.transition
    @transition_status = result.status
    @reason_code = result.reason_code
  rescue Conversations::AutomationTransitionService::Conflict => e
    render_conflict(e)
  rescue Conversations::AutomationTransitionService::FeatureDisabled
    render_feature_disabled
  rescue Conversations::AutomationTransitionService::InvalidRequest => e
    render json: { error: 'invalid_transition', reason_code: e.reason_code }, status: :unprocessable_entity
  end

  private

  def transition_service
    Conversations::AutomationTransitionService.new(
      account: Current.account,
      actor: Current.user,
      account_user: Current.account_user,
      conversation_display_id: params[:conversation_id],
      attributes: transition_params
    )
  end

  def transition_params
    ActionController::Parameters.new(request.request_parameters)
                                .permit(
                                  :action, :idempotency_key, :expected_last_message_id,
                                  :expected_assignee_id, :expected_session_generation
                                )
  end

  def render_feature_disabled
    render json: { error: 'feature_disabled' }, status: :not_found
  end

  def render_conflict(error)
    @conversation = error.conversation.reload
    @transition = nil
    @transition_status = 'conflict'
    @reason_code = error.reason_code
    render :create, status: :conflict
  end
end
