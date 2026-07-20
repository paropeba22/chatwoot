class TechnicalIncidents::OutboxConversationWriter
  def initialize(delivery:, lease:, adapter:, conversation: nil)
    @delivery = delivery
    @lease = lease
    @adapter = adapter
    @conversation = conversation || delivery.conversation
  end

  def ensure_link!
    return if @delivery.link_state == 'completed'

    link = find_or_create_link
    @lease.update!(technical_incident_conversation_link: link, link_state: 'completed')
  end

  def ensure_message!
    return if @delivery.message_state.in?(%w[not_required created])

    message = @adapter.create_message!
    @lease.update!(message_attributes(message))
  rescue StandardError
    @lease.update!(message_state: 'failed_retryable')
    raise
  end

  def ensure_labels!
    return if step_complete?(:label)

    @conversation.update_labels(required_labels)
    @lease.update!(label_state: 'completed')
  rescue StandardError
    @lease.update!(label_state: 'failed_retryable')
    raise
  end

  def ensure_note!
    return if step_complete?(:note)

    create_note! unless existing_note
    @lease.update!(note_state: 'completed')
  rescue StandardError
    @lease.update!(note_state: 'failed_retryable')
    raise
  end

  def ensure_handoff!
    return if step_complete?(:handoff)

    @conversation.update!(assignee_agent_bot_id: nil) if @conversation.assignee_agent_bot_id.present?
    @conversation.bot_handoff!
    @lease.update!(handoff_state: 'completed', state: 'handoff_completed', handoff_completed_at: Time.current)
  rescue StandardError
    @lease.update!(handoff_state: 'failed_retryable')
    raise
  end

  def ensure_audit!
    return if @delivery.audit_state == 'completed'

    record_audit! unless existing_audit
    @lease.update!(audit_state: 'completed')
  rescue StandardError
    @lease.update!(audit_state: 'failed_retryable')
    raise
  end

  private

  def find_or_create_link
    @delivery.account.technical_incident_conversation_links.find_or_create_by!(link_identity) do |record|
      record.technical_incident_evaluation = evaluation
    end
  end

  def link_identity
    {
      technical_incident: @delivery.technical_incident,
      conversation: @delivery.conversation,
      contract_reference: evaluation.selected_contract['contract_id'].to_s,
      notification_version: @delivery.technical_incident.notification_version
    }
  end

  def message_attributes(message)
    {
      message: message,
      message_state: 'created',
      state: 'message_created',
      provider: 'api_inbox_webhook',
      provider_reference: "technical-incident-#{@delivery.id}"
    }
  end

  def required_labels
    (@conversation.label_list - ['bot-bia']) |
      ['aguardando-humano', "incidente-tecnico-#{@delivery.technical_incident_id}"]
  end

  def existing_note
    @conversation.messages
             .where(private: true)
             .find_by("content_attributes ->> 'technical_incident_delivery_id' = ?", @delivery.id.to_s)
  end

  def create_note!
    @conversation.messages.create!(note_attributes)
  end

  def note_attributes
    {
      account: @delivery.account,
      inbox: @conversation.inbox,
      message_type: :outgoing,
      private: true,
      sender: nil,
      content: "Incidente tecnico ##{@delivery.technical_incident_id} vinculado automaticamente.",
      content_attributes: note_content_attributes
    }
  end

  def note_content_attributes
    {
      technical_incident_delivery_id: @delivery.id,
      technical_incident_outbox_managed: true,
      technical_incident_private_note: true
    }
  end

  def existing_audit
    @delivery.technical_incident.updates.find_by(action: 'commit.completed', request_id: evaluation.request_id)
  end

  def record_audit!
    TechnicalIncidents::AuditService.record!(
      incident: @delivery.technical_incident,
      action: 'commit.completed',
      actor: evaluation.agent_bot,
      origin: 'automation',
      request_id: evaluation.request_id,
      changeset: audit_changeset
    )
  end

  def audit_changeset
    {
      conversation_id: @delivery.conversation_id,
      delivery_id: @delivery.id,
      message_id: @delivery.message_id,
      match_source: evaluation.match_source
    }
  end

  def evaluation
    @evaluation ||= @delivery.technical_incident_evaluation
  end

  def step_complete?(step)
    @delivery.public_send("#{step}_state").in?(%w[not_required completed])
  end
end
