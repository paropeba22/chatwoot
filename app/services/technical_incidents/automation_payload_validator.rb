class TechnicalIncidents::AutomationPayloadValidator
  PRECHECK_KEYS = %w[
    conversation_display_id source_message_id mode request_id idempotency_key contract_version
    classification semantic_classification controller action format
  ].freeze
  MATCH_KEYS = %w[selected_contract_id selected_contract contracts sanitized_contracts controller action id format].freeze
  COMMIT_KEYS = %w[controller action id format].freeze
  LOCATION_KEYS = %w[state city neighborhood postal_code street number].freeze

  def initialize(params)
    @params = params
  end

  def validate_precheck
    return 'unexpected_precheck_field' if unexpected_keys?(@params, PRECHECK_KEYS)

    classification = @params[:classification] || @params[:semantic_classification] || {}
    return 'unexpected_classification_field' if unexpected_keys?(classification, TechnicalIncidents::SemanticFilter::ALLOWED_CLASSIFICATION_KEYS)
  end

  def validate_match
    return 'unexpected_match_field' if unexpected_keys?(@params, MATCH_KEYS)
    return 'too_many_contracts' if contracts.length > 20
    return 'contract_contains_forbidden_fields' if contracts.any? { |contract| forbidden_contract_fields?(contract) }
    return 'unexpected_selected_contract_field' if unexpected_keys?(selected_contract, ['contract_id'])
  end

  def validate_commit
    'unexpected_commit_field' if unexpected_keys?(@params, COMMIT_KEYS)
  end

  private

  def contracts
    Array(@params[:contracts] || @params[:sanitized_contracts])
  end

  def selected_contract
    @params[:selected_contract] || {}
  end

  def forbidden_contract_fields?(contract)
    unexpected_keys?(contract, TechnicalIncidents::MatchService::ALLOWED_CONTRACT_KEYS) ||
      unexpected_keys?(contract[:location] || contract['location'] || {}, LOCATION_KEYS)
  end

  def unexpected_keys?(value, allowed)
    (value.keys.map(&:to_s) - allowed).any?
  end
end
