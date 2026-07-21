class TechnicalIncidents::DeliveryAdapters
  ADAPTERS = {
    'Channel::Api' => TechnicalIncidents::DeliveryAdapters::ApiInbox
  }.freeze

  def self.for(delivery)
    ADAPTERS.fetch(
      delivery.conversation.inbox.channel_type,
      TechnicalIncidents::DeliveryAdapters::Base
    ).new(delivery)
  end
end
