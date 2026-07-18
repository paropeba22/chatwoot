require 'rails_helper'

RSpec.describe Featurable do
  it 'preserves every existing bigint bit and keeps technical incidents in a dedicated boolean' do
    expect(described_class::FEATURES.size).to eq(63)
    expect(described_class::FEATURES.fetch(63)).to eq(:feature_advanced_assignment)
    expect(described_class::FEATURES.value?(:feature_technical_incidents)).to be(false)
  end

  it 'uses the standard feature API without touching feature_flags' do
    account = create(:account)
    original_flags = account.feature_flags

    account.enable_features!('technical_incidents')
    expect(account.reload).to be_feature_enabled('technical_incidents')
    expect(account.feature_flags).to eq(original_flags)

    account.disable_features!('technical_incidents')
    expect(account.reload).not_to be_feature_enabled('technical_incidents')
    expect(account.feature_flags).to eq(original_flags)
  end

  it 'supports the super-admin bulk feature setter without shifting existing bits' do
    account = create(:account)
    existing_feature = described_class::FEATURES.values.first

    account.selected_feature_flags = [existing_feature, :feature_technical_incidents]

    expect(account.public_send("#{existing_feature}?")).to be(true)
    expect(account).to be_feature_enabled('technical_incidents')
  end
end
