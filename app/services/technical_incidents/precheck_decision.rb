class TechnicalIncidents::PrecheckDecision
  def initialize(account:, classification:, semantic_gate:)
    @account = account
    @classification = classification
    @semantic_gate = semantic_gate
  end

  def call
    return blocked_outcome unless @semantic_gate.allowed

    candidates = compatible_candidates
    decision = candidates.empty? ? inactive_decision : active_decision(candidates)
    decision.merge(candidates: candidates)
  end

  private

  def blocked_outcome
    { status: @semantic_gate.status, reason_code: @semantic_gate.reason_code, candidates: [] }
  end

  def active_decision(candidates)
    localized = candidates.reject(&:general_scope?)
    return localized_decision(localized.first) if localized.any?

    general_decision(candidates.select(&:general_scope?))
  end

  def localized_decision(incident)
    { status: 'localized_candidate', reason_code: 'localized_candidates_available', incident: incident }
  end

  def general_decision(incidents)
    ranked = TechnicalIncidents::CandidateRanker.sort(
      incidents.map { |incident| { incident: incident, specificity: 0 } }
    )
    return no_candidate if ranked.empty?
    return { status: 'ambiguous', reason_code: 'general_candidate_tie' } if ambiguous?(ranked)

    { status: 'general_match', reason_code: 'semantic_general_match', incident: ranked.first[:incident] }
  end

  def inactive_decision
    compatible = inactive_candidates
    return { status: 'fallback', reason_code: 'incident_monitoring' } if status_present?(compatible, 'monitoring')
    return { status: 'expired', reason_code: 'incident_expired' } if expired?(compatible)

    no_candidate
  end

  def compatible_candidates
    candidates = semantic_scope(@account.technical_incidents.intercepting)
                 .includes(scope_groups: :criteria)
                 .select { |incident| compatible?(incident) }
    return candidates if @semantic_gate.confidence_level == 'high'

    candidates.select { |incident| allowed_exact_scope?(incident) }
  end

  def inactive_candidates
    semantic_scope(@account.technical_incidents.not_archived.where(status: %w[active monitoring expired]))
      .includes(scope_groups: :criteria)
      .select { |incident| compatible?(incident) }
  end

  def semantic_scope(scope)
    scoped = scope.where('problem_types @> ARRAY[?]::text[]', @classification['problem_type'])
    return scoped.where('cardinality(affected_services) = 0') unless valid_service_key?

    scoped.where('cardinality(affected_services) = 0 OR affected_services @> ARRAY[?]::text[]', service_key)
  end

  def allowed_exact_scope?(incident)
    incident.scope_groups.any? do |group|
      group.criteria.any? { |criterion| @semantic_gate.allowed_match_sources.include?(criterion.criterion_type) }
    end
  end

  def compatible?(incident)
    TechnicalIncidents::SemanticFilter.compatible?(incident, @classification)
  end

  def valid_service_key?
    TechnicalIncident::SERVICE_KEYS.include?(service_key)
  end

  def service_key
    @classification['service_key']
  end

  def ambiguous?(ranked)
    TechnicalIncidents::CandidateRanker.ambiguous?(ranked)
  end

  def status_present?(incidents, status)
    incidents.any? { |incident| incident.status == status }
  end

  def expired?(incidents)
    incidents.any? { |incident| incident.status == 'expired' || expired_window?(incident) }
  end

  def expired_window?(incident)
    incident.expires_at.present? && incident.expires_at <= Time.current
  end

  def no_candidate
    { status: 'no_candidate', reason_code: 'no_semantic_candidate' }
  end
end
