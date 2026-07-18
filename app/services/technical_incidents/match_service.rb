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
      return response('stale', 'evaluation_expired') if @evaluation.stale?
      return response('stale', 'feature_disabled') unless @account.feature_enabled?('technical_incidents')
      return response(@evaluation.status, @evaluation.reason_code) if @evaluation.status == 'matched'
      return response('stale', 'evaluation_not_matchable') unless MATCHABLE_STATUSES.include?(@evaluation.status)

      contracts = sanitized_contracts
      if contracts.length > 1 && selected_contract_id.blank?
        update_evaluation!('needs_contract_selection', nil, contracts, reason_code: 'multiple_contracts_require_selection')
        return response(@evaluation.status, @evaluation.reason_code)
      end

      selected = select_contract(contracts)
      unless selected
        update_evaluation!('needs_contract_selection', nil, contracts, reason_code: 'selected_contract_not_found')
        return response(@evaluation.status, @evaluation.reason_code)
      end

      matches = candidate_incidents.filter_map do |incident|
        match = TechnicalIncidents::Matcher.new(
          incident: incident,
          contract: selected,
          classification: @evaluation.classification
        ).call
        match&.merge(incident: incident)
      end
      ranked = TechnicalIncidents::CandidateRanker.sort(matches)
      if ranked.empty?
        update_evaluation!('no_candidate', selected, contracts, reason_code: 'no_deterministic_match')
      elsif TechnicalIncidents::CandidateRanker.ambiguous?(ranked)
        update_evaluation!('ambiguous', selected, contracts, reason_code: 'deterministic_match_tie')
      else
        winner = ranked.first
        update_evaluation!(
          'matched',
          selected,
          contracts,
          incident: winner[:incident],
          match_source: winner[:match_source],
          reason_code: "matched_by_#{winner[:match_source]}"
        )
      end
      response(@evaluation.status, @evaluation.reason_code)
    end
  rescue ArgumentError => e
    response('fallback', e.message)
  end

  private

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

  def candidate_incidents
    ids = Array(@evaluation.candidate_snapshot).pluck('id')
    @account.technical_incidents.intercepting.includes(scope_groups: :criteria).where(id: ids)
  end

  def update_evaluation!(status, selected, contracts, incident: nil, match_source: nil, reason_code:)
    @evaluation.update!(
      status: status,
      selected_contract: selected,
      sanitized_contracts: contracts,
      technical_incident: incident,
      match_source: match_source,
      reason_code: reason_code
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
