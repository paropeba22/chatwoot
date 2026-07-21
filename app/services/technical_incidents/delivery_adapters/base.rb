class TechnicalIncidents::DeliveryAdapters::Base
  class UnsupportedInbox < StandardError; end
  class DeliveryDisabled < StandardError; end

  def initialize(delivery)
    @delivery = delivery
  end

  def create_message!
    raise UnsupportedInbox, @delivery.conversation.inbox.channel_type
  end

  def enqueue_transport!(_message)
    raise UnsupportedInbox, @delivery.conversation.inbox.channel_type
  end
end
