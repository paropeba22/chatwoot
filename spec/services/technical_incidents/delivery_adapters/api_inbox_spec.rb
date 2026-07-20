require 'rails_helper'

RSpec.describe TechnicalIncidents::DeliveryAdapters::ApiInbox do
  subject(:adapter) { described_class.new(Object.new) }

  it 'blocks message creation and transport while global delivery is disabled' do
    with_modified_env(
      TECHNICAL_INCIDENTS_DELIVERY_ENABLED: 'false',
      TECHNICAL_INCIDENTS_API_INBOX_DELIVERY_ENABLED: 'true'
    ) do
      expect { adapter.create_message! }
        .to raise_error(TechnicalIncidents::DeliveryAdapters::Base::DeliveryDisabled, 'delivery_disabled')
      expect { adapter.enqueue_transport!(Object.new) }
        .to raise_error(TechnicalIncidents::DeliveryAdapters::Base::DeliveryDisabled, 'delivery_disabled')
    end
  end

  it 'blocks message creation and webhooks until API Inbox delivery is explicitly verified' do
    expect(WebhookJob).not_to receive(:perform_later)

    with_modified_env(
      TECHNICAL_INCIDENTS_DELIVERY_ENABLED: 'true',
      TECHNICAL_INCIDENTS_API_INBOX_DELIVERY_ENABLED: 'false'
    ) do
      expect { adapter.create_message! }
        .to raise_error(TechnicalIncidents::DeliveryAdapters::Base::DeliveryDisabled, 'api_inbox_delivery_unverified')
      expect { adapter.enqueue_transport!(Object.new) }
        .to raise_error(TechnicalIncidents::DeliveryAdapters::Base::DeliveryDisabled, 'api_inbox_delivery_unverified')
    end
  end
end
