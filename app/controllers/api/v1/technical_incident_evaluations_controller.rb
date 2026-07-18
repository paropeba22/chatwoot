class Api::V1::TechnicalIncidentEvaluationsController < Api::BaseController
  before_action :set_actor_and_account

  def feedback
    return unless valid_feedback_shape?

    evaluation = Current.account.technical_incident_evaluations.find_by!(opaque_id: params[:id])
    return render json: { error: 'feature_disabled' }, status: :not_found unless Current.account.feature_enabled?('technical_incidents')

    authorize(evaluation.technical_incident, :history?, policy_class: TechnicalIncidentPolicy) if Current.user.is_a?(User)
    TechnicalIncidents::FeedbackService.new(
      evaluation: evaluation,
      feedback: feedback_params.require(:feedback),
      note: feedback_params[:note],
      actor: Current.user
    ).call
    render json: { status: 'accepted', evaluation_id: evaluation.opaque_id }
  end

  private

  def set_actor_and_account
    if Current.user.is_a?(AgentBot)
      unless Current.user.bot_config.to_h['technical_incidents_api'] == true
        return render_unauthorized('Dedicated technical incidents AgentBot token required')
      end

      Current.account = Current.user.account
      render_unauthorized('Account-scoped AgentBot required') unless Current.account
    elsif Current.user.is_a?(User)
      Current.account = Current.user.accounts.find(params.require(:account_id))
      Current.account_user = Current.account.account_users.find_by!(user: Current.user)
    end
  end

  def feedback_params
    params.permit(:account_id, :feedback, :note)
  end

  def valid_feedback_shape?
    allowed = %w[account_id feedback note controller action id format]
    return true if (params.keys - allowed).empty?

    render json: {
      contract_version: TechnicalIncidents::PrecheckService::CONTRACT_VERSION,
      status: 'fallback',
      reason_code: 'unexpected_feedback_field'
    }, status: :unprocessable_entity
    false
  end
end
