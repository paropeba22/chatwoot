class TechnicalIncidents::CommitService
  class StaleEvaluation < StandardError; end

  def initialize(account:, opaque_id:)
    @account = account
    @opaque_id = opaque_id
  end

  def call
    delivery = nil
    duplicate_response = nil
    idempotency_key_value = nil
    ActiveRecord::Base.transaction do
      @account.lock!
      evaluation = @account.technical_incident_evaluations.lock.find_by!(opaque_id: @opaque_id)
      incident = evaluation.technical_incident&.lock!
      raise StaleEvaluation, 'feature_disabled' unless @account.feature_enabled?('technical_incidents')
      if evaluation.status == 'accepted'
        existing = @account.technical_incident_deliveries.find_by(technical_incident_evaluation: evaluation)
        raise StaleEvaluation, 'accepted_delivery_missing' unless existing

        duplicate_response = response(existing, 'duplicate', 'idempotency_key_exists')
        next
      end

      validate!(evaluation, incident)
      idempotency_key_value = idempotency_key(evaluation, incident)
      existing = @account.technical_incident_deliveries.find_by(idempotency_key: idempotency_key_value)
      if existing
        duplicate_response = response(existing, 'duplicate', 'idempotency_key_exists')
        next
      end

      delivery = reserve_delivery!(evaluation, incident, idempotency_key_value)
      link = create_link!(evaluation, incident)
      delivery.update!(technical_incident_conversation_link: link)
      message = create_customer_message!(evaluation, incident) unless incident.action == 'handoff_only'
      if message
        delivery.update!(message: message, state: 'message_created')
        delivery.update!(state: 'delivery_queued', delivery_queued_at: Time.current)
      end
      if incident.action != 'message_only'
        apply_handoff!(evaluation.conversation, incident)
        delivery.update!(state: 'handoff_completed', handoff_completed_at: Time.current)
      end
      evaluation.update!(status: 'accepted', committed_at: Time.current)
      TechnicalIncidents::AuditService.record!(
        incident: incident,
        action: 'commit.accepted',
        actor: evaluation.agent_bot,
        origin: 'automation',
        request_id: evaluation.request_id,
        changeset: {
          conversation_id: evaluation.conversation_id,
          delivery_id: delivery.id,
          message_id: message&.id,
          match_source: evaluation.match_source,
          contract_reference: contract_reference(evaluation)
        }
      )
    end
    return duplicate_response if duplicate_response

    response(delivery, 'accepted', 'commit_completed')
  rescue ActiveRecord::RecordNotFound
    { contract_version: TechnicalIncidents::PrecheckService::CONTRACT_VERSION, status: 'stale', reason_code: 'evaluation_not_found' }
  rescue StaleEvaluation => e
    { contract_version: TechnicalIncidents::PrecheckService::CONTRACT_VERSION, status: 'stale', reason_code: e.message }
  rescue ActiveRecord::RecordNotUnique
    existing = @account.technical_incident_deliveries.find_by(idempotency_key: idempotency_key_value)
    response(existing, 'duplicate', 'concurrent_commit')
  end

  private

  def validate!(evaluation, incident)
    raise StaleEvaluation, 'feature_disabled' unless @account.feature_enabled?('technical_incidents')
    raise StaleEvaluation, 'evaluation_not_active_mode' unless evaluation.mode == 'active'
    raise StaleEvaluation, 'evaluation_expired' if evaluation.stale?
    raise StaleEvaluation, 'evaluation_not_matched' unless evaluation.status.in?(%w[general_match matched])
    raise StaleEvaluation, 'incident_unavailable' unless incident&.active_and_current?
    raise StaleEvaluation, 'notification_version_changed' unless snapshot_version(evaluation) == incident.notification_version
    raise StaleEvaluation, 'conversation_unavailable' unless evaluation.conversation.account_id == @account.id
    raise StaleEvaluation, 'automation_actor_missing' unless evaluation.agent_bot
    unless evaluation.agent_bot.bot_config.to_h['technical_incidents_api'] == true
      raise StaleEvaluation, 'automation_actor_invalid'
    end
    raise StaleEvaluation, 'selected_contract_missing' if evaluation.status == 'matched' && evaluation.selected_contract['contract_id'].blank?
    raise StaleEvaluation, 'semantic_compatibility_changed' unless TechnicalIncidents::SemanticFilter.compatible?(incident, evaluation.classification)

    revalidate_scope!(evaluation, incident)
  end

  def revalidate_scope!(evaluation, incident)
    if evaluation.status == 'general_match'
      raise StaleEvaluation, 'general_scope_changed' unless incident.general_scope?
      return
    end

    match = TechnicalIncidents::Matcher.new(
      incident: incident,
      contract: evaluation.selected_contract,
      classification: evaluation.classification
    ).call
    raise StaleEvaluation, 'deterministic_match_changed' unless match
    return if match[:match_source] == evaluation.match_source

    raise StaleEvaluation, 'match_source_changed'
  end

  def snapshot_version(evaluation)
    snapshot = Array(evaluation.candidate_snapshot).find { |candidate| candidate['id'] == evaluation.technical_incident_id }
    snapshot&.fetch('notification_version', nil)
  end

  def idempotency_key(evaluation, incident)
    [
      evaluation.conversation_id,
      incident.id,
      incident.notification_version,
      delivery_kind(incident)
    ].join(':')
  end

  def delivery_kind(incident)
    return 'initial' if incident.notification_version == 1

    reopening = incident.updates
                        .where(action: %w[transition.resolved.active transition.expired.active transition.cancelled.active])
                        .order(id: :desc)
                        .find do |update|
      Array(update.changeset['notification_version']).last == incident.notification_version
    end
    reopening ? 'reopening' : 'update'
  end

  def reserve_delivery!(evaluation, incident, key)
    @account.technical_incident_deliveries.create!(
      technical_incident: incident,
      technical_incident_evaluation: evaluation,
      conversation: evaluation.conversation,
      idempotency_key: key,
      delivery_kind: delivery_kind(incident),
      state: 'reserved'
    )
  end

  def create_link!(evaluation, incident)
    @account.technical_incident_conversation_links.create_or_find_by!(
      technical_incident: incident,
      conversation: evaluation.conversation,
      technical_incident_evaluation: evaluation,
      contract_reference: contract_reference(evaluation),
      notification_version: incident.notification_version
    )
  end

  def create_customer_message!(evaluation, incident)
    Messages::MessageBuilder.new(
      evaluation.agent_bot,
      evaluation.conversation,
      {
        content: TechnicalIncidents::TemplateRenderer.render(incident),
        message_type: 'outgoing',
        sender_type: 'AgentBot',
        sender_id: evaluation.agent_bot_id,
        content_type: 'text',
        content_attributes: {
          technical_incident_id: incident.id,
          technical_incident_version: incident.notification_version,
          technical_incident_delivery: true
        }
      }
    ).perform
  end

  def apply_handoff!(conversation, incident)
    labels = conversation.label_list - ['bot-bia']
    labels |= ['aguardando-humano', "incidente-tecnico-#{incident.id}"]
    conversation.update_labels(labels)
    conversation.update!(assignee_agent_bot_id: nil)
    conversation.bot_handoff!
    conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      private: true,
      sender: nil,
      content: "Incidente técnico ##{incident.id} vinculado automaticamente. Correspondência revalidada pelo backend."
    )
  end

  def contract_reference(evaluation)
    evaluation.selected_contract['contract_id'].to_s
  end

  def response(delivery, status, reason_code)
    {
      contract_version: TechnicalIncidents::PrecheckService::CONTRACT_VERSION,
      status: status,
      reason_code: reason_code,
      delivery_id: delivery&.id,
      delivery_state: delivery&.state,
      message_id: delivery&.message_id
    }.compact
  end
end
