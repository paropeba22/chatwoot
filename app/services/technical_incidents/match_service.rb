class TechnicalIncidents::MatchService
  MATCHABLE_STATUSES = %w[localized_candidate needs_document needs_contract_selection].freeze
  ALLOWED_CONTRACT_KEYS = %w[
    contract_id status pop_id pop_name service_group connection_type state city neighborhood postal_code street number location
  ].freeze

  def initialize(account:, evaluation:, payload:)
    @account = account
    @evaluation = evaluation
    @payload = payload.to_h.deep_stringify_keys
  end

  def call
    @evaluation.with_lock do
      @evaluation.reload
      @result = process_locked
    end
    @result
  rescue ArgumentError => e
    record_failure(e.message)
    response('fallback', e.message)
  end

  private

  def process_locked
    blocked = eligibility_response
    return blocked if blocked

    contracts = sanitized_contracts
    selection = contract_selection(contracts)
    return selection[:response] if selection[:response]

    update_evaluation!(match_decision(selection[:contract], contracts))
    record_match
    response(@evaluation.status, @evaluation.reason_code)
  end

  def eligibility_response
    return response('fallback', 'server_automation_disabled') if automation_disabled?
    return response('stale', 'evaluation_expired') if @evaluation.stale?
    return response('stale', 'feature_disabled') unless @account.feature_enabled?('technical_incidents')
    return response('stale', 'account_mismatch') unless @evaluation.account_id == @account.id

    semantic_gate_response || evaluation_status_response
  end

  def semantic_gate_response
    gate = TechnicalIncidents::SemanticGate.call(@evaluation.classification)
    response(gate.status, gate.reason_code) unless gate.allowed
  end

  def evaluation_status_response
    return response(@evaluation.status, @evaluation.reason_code) if @evaluation.status == 'matched'
    return if MATCHABLE_STATUSES.include?(@evaluation.status)

    response('stale', 'evaluation_not_matchable')
  end

  def automation_disabled?
    TechnicalIncidents::Configuration.automation_mode == 'disabled'
  end

  def sanitized_contracts
    raw_contracts = Array(@payload['contracts'] || @payload['sanitized_contracts'])
    raw_contracts.map do |raw|
      unknown = raw.to_h.stringify_keys.keys - ALLOWED_CONTRACT_KEYS
      raise ArgumentError, 'contract_contains_forbidden_fields' if unknown.any?

      TechnicalIncidents::Normalizer.contract(raw)
    end.first(20)
  end

  def selected_contract_id
    @payload['selected_contract_id'].presence || @payload.dig('selected_contract', 'contract_id').presence
  end

  def select_contract(contracts)
    return contracts.first if contracts.one?

    contracts.find { |contract| contract['contract_id'] == selected_contract_id.to_s }
  end

  def contract_selection(contracts)
    return selection_required(contracts, 'multiple_contracts_require_selection') if selection_missing?(contracts)

    selected = select_contract(contracts)
    return selection_required(contracts, 'selected_contract_not_found') unless selected

    { contract: selected }
  end

  def selection_missing?(contracts)
    contracts.length > 1 && selected_contract_id.blank?
  end

  def selection_required(contracts, reason_code)
    update_evaluation!(status: 'needs_contract_selection', contracts: contracts, reason_code: reason_code)
    { response: response(@evaluation.status, @evaluation.reason_code) }
  end

  def candidate_incidents
    ids = Array(@evaluation.candidate_snapshot).pluck('id')
    @account.technical_incidents.intercepting.includes(scope_groups: :criteria).where(id: ids)
  end

  def match_decision(selected, contracts)
    ranked = TechnicalIncidents::CandidateRanker.sort(matches_for(selected))
    return no_match_decision(selected, contracts) if ranked.empty?
    return ambiguous_decision(selected, contracts) if TechnicalIncidents::CandidateRanker.ambiguous?(ranked)

    matched_decision(ranked.first, selected, contracts)
  end

  def matches_for(selected)
    candidate_incidents.filter_map do |incident|
      match = TechnicalIncidents::Matcher.new(
        incident: incident,
        contract: selected,
        classification: @evaluation.classification
      ).call
      match&.merge(incident: incident)
    end
  end

  def no_match_decision(selected, contracts)
    { status: 'no_candidate', selected: selected, contracts: contracts, reason_code: 'no_deterministic_match' }
  end

  def ambiguous_decision(selected, contracts)
    { status: 'ambiguous', selected: selected, contracts: contracts, reason_code: 'deterministic_match_tie' }
  end

  def matched_decision(winner, selected, contracts)
    {
      status: 'matched',
      selected: selected,
      contracts: contracts,
      incident: winner[:incident],
      match_source: winner[:match_source],
      reason_code: "matched_by_#{winner[:match_source]}"
    }
  end

  def update_evaluation!(decision)
    @evaluation.update!(
      status: decision[:status],
      selected_contract: decision[:selected] || {},
      sanitized_contracts: decision[:contracts] || [],
      technical_incident: decision[:incident],
      match_source: decision[:match_source],
      reason_code: decision[:reason_code]
    )
  end

  def record_match
    TechnicalIncidents::Instrumentation.record(
      event: 'match',
      request_id: @evaluation.request_id,
      evaluation_id: @evaluation.opaque_id,
      incident_id: @evaluation.technical_incident_id,
      conversation_id: @evaluation.conversation_id,
      status: @evaluation.status,
      reason_code: @evaluation.reason_code,
      match_source: @evaluation.match_source
    )
  end

  def record_failure(reason_code)
    TechnicalIncidents::Instrumentation.record(
      event: 'match', evaluation_id: @evaluation.opaque_id, status: 'fallback', reason_code: reason_code
    )
  end

  def response(status, reason_code)
    incident = @evaluation.technical_incident
    {
      contract_version: TechnicalIncidents::PrecheckService::CONTRACT_VERSION,
      id: @evaluation.opaque_id,
      check_id: @evaluation.opaque_id,
      evaluation_id: @evaluation.opaque_id,
      commit_token: @evaluation.opaque_id,
      status: status,
      reason_code: reason_code,
      match_source: @evaluation.match_source,
      incident: incident&.customer_visible_snapshot,
      customer_message: incident && TechnicalIncidents::TemplateRenderer.render(incident),
      notification_version: incident&.notification_version
    }.compact
  end
end
