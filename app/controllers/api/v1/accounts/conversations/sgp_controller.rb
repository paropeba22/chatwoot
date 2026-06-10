class Api::V1::Accounts::Conversations::SgpController < Api::V1::Accounts::Conversations::BaseController
  def create
    result = processor_service.perform(
      action: permitted_params[:sgp_action],
      cpf_cnpj: permitted_params[:cpf_cnpj],
      fatura_id: permitted_params[:fatura_id]
    )

    render json: result, status: response_status(result)
  end

  private

  def processor_service
    Integrations::Sgp::ProcessorService.new(
      account: Current.account,
      conversation: @conversation,
      user: Current.user
    )
  end

  def permitted_params
    params.permit(:sgp_action, :cpf_cnpj, :fatura_id)
  end

  def response_status(result)
    return :ok if result[:ok]
    return :service_unavailable if %w[sgp_indisponivel configuracao_incompleta].include?(result[:reason])

    :unprocessable_entity
  end
end
