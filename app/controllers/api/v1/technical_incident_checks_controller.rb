class Api::V1::TechnicalIncidentChecksController < Api::BaseController
  include TechnicalIncidentAutomationSecurity

  before_action :ensure_agent_bot!
  before_action :set_automation_account
  before_action :ensure_technical_incident_https!
  before_action :enforce_technical_incident_account_rate_limit!

  def precheck
    return unless valid_precheck_shape?

    render json: TechnicalIncidents::PrecheckService.new(
      account: Current.account,
      agent_bot: Current.user,
      payload: precheck_params
    ).call
  end

  def match
    return unless valid_match_shape?

    evaluation = Current.account.technical_incident_evaluations.find_by!(opaque_id: params[:id])
    render json: TechnicalIncidents::MatchService.new(
      account: Current.account,
      evaluation: evaluation,
      payload: match_params
    ).call
  end

  def commit
    return unless valid_commit_shape?

    render json: TechnicalIncidents::CommitService.new(account: Current.account, opaque_id: params[:id]).call
  end

  private

  def ensure_agent_bot!
    authorized = Current.user.is_a?(AgentBot) && Current.user.bot_config.to_h['technical_incidents_api'] == true
    render_unauthorized('Dedicated technical incidents AgentBot token required') unless authorized
  end

  def set_automation_account
    Current.account = Current.user.account
    render_unauthorized('Account-scoped AgentBot required') unless Current.account
  end

  def precheck_params
    params.permit(
      :conversation_display_id, :source_message_id, :mode, :request_id, :idempotency_key, :contract_version,
      classification: [
        :is_support_issue, :problem_type, :service_key, :semantic_confidence,
        :topic_change, :needs_clarification, :reason_code, { symptoms: [] }
      ],
      semantic_classification: [
        :is_support_issue, :problem_type, :service_key, :semantic_confidence,
        :topic_change, :needs_clarification, :reason_code, { symptoms: [] }
      ]
    ).to_h
  end

  def match_params
    permitted_contract = [
      :contract_id, :status, :pop_id, :pop_name, :service_group, :connection_type,
      :state, :city, :neighborhood, :postal_code, :street, :number,
      { location: [:state, :city, :neighborhood, :postal_code, :street, :number] }
    ]
    params.permit(
      :selected_contract_id,
      selected_contract: [:contract_id],
      contracts: permitted_contract,
      sanitized_contracts: permitted_contract
    ).to_h
  end

  def valid_precheck_shape?
    validate_contract_shape(:precheck)
  end

  def valid_match_shape?
    validate_contract_shape(:match)
  end

  def valid_commit_shape?
    validate_contract_shape(:commit)
  end

  def validate_contract_shape(action)
    reason_code = TechnicalIncidents::AutomationPayloadValidator.new(params).public_send("validate_#{action}")
    return true unless reason_code

    render_invalid_contract(reason_code)
  end

  def render_invalid_contract(reason_code)
    render json: {
      contract_version: TechnicalIncidents::PrecheckService::CONTRACT_VERSION,
      status: 'fallback',
      reason_code: reason_code
    }, status: :unprocessable_entity
    false
  end
end
