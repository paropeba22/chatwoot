class TechnicalIncidents::DeliveryAdapters::ApiInbox < TechnicalIncidents::DeliveryAdapters::Base
  def create_message!
    ensure_enabled!
    existing_message || Messages::MessageBuilder.new(
      evaluation.agent_bot,
      conversation,
      {
        content: TechnicalIncidents::TemplateRenderer.render(incident),
        message_type: 'outgoing',
        sender_type: 'AgentBot',
        sender_id: evaluation.agent_bot_id,
        content_type: 'text',
        content_attributes: {
          technical_incident_id: incident.id,
          technical_incident_version: incident.notification_version,
          technical_incident_delivery_id: @delivery.id,
          technical_incident_outbox_managed: true
        }
      }
    ).perform
  rescue StandardError
    message = existing_message
    return message if message

    raise
  end

  def enqueue_transport!(message)
    ensure_enabled!
    channel = conversation.inbox.channel
    raise UnsupportedInbox, 'api_inbox_webhook_missing' if channel.webhook_url.blank?

    WebhookJob.perform_later(
      channel.webhook_url,
      message.webhook_data.merge(event: 'message_created'),
      :api_inbox_webhook,
      secret: channel.secret,
      delivery_id: "technical-incident-#{@delivery.id}"
    )
    'api_inbox_webhook'
  end

  private

  def ensure_enabled!
    raise DeliveryDisabled, 'delivery_disabled' unless TechnicalIncidents::Configuration.delivery_enabled?
    return if TechnicalIncidents::Configuration.api_inbox_delivery_enabled?

    raise DeliveryDisabled, 'api_inbox_delivery_unverified'
  end

  def existing_message
    return @delivery.message if @delivery.message

    conversation.messages
                .where("content_attributes ->> 'technical_incident_delivery_id' = ?", @delivery.id.to_s)
                .first
  end

  def conversation
    @delivery.conversation
  end

  def evaluation
    @delivery.technical_incident_evaluation
  end

  def incident
    @delivery.technical_incident
  end
end
