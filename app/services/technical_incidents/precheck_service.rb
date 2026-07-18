class TechnicalIncidents::PrecheckService
  CONTRACT_VERSION = '1.0'.freeze

  def initialize(account:, agent_bot:, payload:)
    @account = account
    @agent_bot = agent_bot
    @payload = payload.to_h.deep_stringify_keys
  end

  def call
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    classification = TechnicalIncidents::SemanticFilter.sanitize(@payload['classification'] || @payload['semantic_classification'])
    validate_payload!(classification)

    existing = @account.technical_incident_evaluations.find_by(request_id: request_id)
    existing ||= @account.technical_incident_evaluations.find_by(source_message_id: @payload['source_message_id']) if @payload['source_message_id'].present?
    return response(existing, duplicate: true) if existing

    conversation = @account.conversations.find_by!(display_id: @payload['conversation_display_id'])
    candidates = @account.technical_incidents.intercepting.includes(scope_groups: :criteria)
                         .select { |incident| TechnicalIncidents::SemanticFilter.compatible?(incident, classification) }
    decision = candidates.empty? ? inactive_decision(classification) : decide(candidates)
    evaluation = @account.technical_incident_evaluations.create!(
      conversation: conversation,
      agent_bot: @agent_bot,
      technical_incident: decision[:incident],
      request_id: request_id,
      source_message_id: @payload['source_message_id'],
      contract_version: CONTRACT_VERSION,
      mode: @payload['mode'],
      status: decision[:status],
      reason_code: decision[:reason_code],
      classification: classification,
      candidate_snapshot: candidates.map(&:customer_visible_snapshot),
      operational_confidence: classification['semantic_confidence'],
      latency_ms: elapsed_ms(started_at),
      expires_at: 20.minutes.from_now
    )

    TechnicalIncidents::AuditService.record!(
      incident: decision[:incident],
      action: 'evaluation.precheck',
      actor: @agent_bot,
      origin: 'automation',
      request_id: request_id,
      changeset: { conversation_id: conversation.id, decision: decision[:status], reason_code: decision[:reason_code] }
    ) if decision[:incident]
    response(evaluation)
  rescue ActiveRecord::RecordNotFound
    { contract_version: CONTRACT_VERSION, status: 'stale', reason_code: 'conversation_not_found' }
  rescue ActiveRecord::RecordNotUnique
    duplicate = @account.technical_incident_evaluations.find_by(request_id: request_id)
    duplicate ||= @account.technical_incident_evaluations.find_by(source_message_id: @payload['source_message_id'])
    response(duplicate, duplicate: true)
  rescue ArgumentError => e
    { contract_version: CONTRACT_VERSION, status: 'fallback', reason_code: e.message }
  end

  private

  def request_id
    @payload['request_id'].presence || @payload['idempotency_key'].presence || raise(ArgumentError, 'request_id_required')
  end

  def validate_payload!(classification)
    raise ArgumentError, 'feature_disabled' unless @account.feature_enabled?('technical_incidents')
    unless @agent_bot && @agent_bot.bot_config.to_h['technical_incidents_api'] == true
      raise ArgumentError, 'automation_actor_invalid'
    end
    raise ArgumentError, 'contract_version_unsupported' unless @payload['contract_version'].to_s == CONTRACT_VERSION
    raise ArgumentError, 'invalid_mode' unless TechnicalIncidentEvaluation::MODES.include?(@payload['mode'])
    raise ArgumentError, 'invalid_classification' unless classification['is_support_issue'].in?([true, false])
  end

  def decide(candidates)
    general = candidates.select(&:general_scope?).map { |incident| { incident: incident, specificity: 0 } }
    localized = candidates.reject(&:general_scope?)
    ranked_general = TechnicalIncidents::CandidateRanker.sort(general)

    # A localized candidate must be resolved against the selected contract before
    # a broader incident can win. MatchService ranks all candidates afterwards.
    if localized.any?
      return { status: 'localized_candidate', reason_code: 'localized_candidates_available', incident: localized.first }
    end

    if ranked_general.any?
      return { status: 'ambiguous', reason_code: 'general_candidate_tie' } if TechnicalIncidents::CandidateRanker.ambiguous?(ranked_general)

      return { status: 'general_match', reason_code: 'semantic_general_match', incident: ranked_general.first[:incident] }
    end

    { status: 'no_candidate', reason_code: 'no_semantic_candidate' }
  end

  def inactive_decision(classification)
    compatible = @account.technical_incidents.not_archived.includes(scope_groups: :criteria)
                         .select { |incident| TechnicalIncidents::SemanticFilter.compatible?(incident, classification) }
    return { status: 'fallback', reason_code: 'incident_monitoring' } if compatible.any? { |incident| incident.status == 'monitoring' }
    if compatible.any? { |incident| incident.status == 'expired' || (incident.expires_at.present? && incident.expires_at <= Time.current) }
      return { status: 'expired', reason_code: 'incident_expired' }
    end

    { status: 'no_candidate', reason_code: 'no_semantic_candidate' }
  end

  def response(evaluation, duplicate: false)
    incident = evaluation.technical_incident
    {
      contract_version: CONTRACT_VERSION,
      id: evaluation.opaque_id,
      check_id: evaluation.opaque_id,
      evaluation_id: evaluation.opaque_id,
      commit_token: evaluation.opaque_id,
      status: duplicate ? 'duplicate' : evaluation.status,
      reason_code: duplicate ? 'duplicate_request' : evaluation.reason_code,
      incident: incident&.customer_visible_snapshot,
      customer_message: incident && TechnicalIncidents::TemplateRenderer.render(incident),
      notification_version: incident&.notification_version,
      expires_at: evaluation.expires_at
    }.compact
  end

  def elapsed_ms(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
  end
end
