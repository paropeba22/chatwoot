require 'rails_helper'

RSpec.describe TechnicalIncidents::ContractReferencePresenter do
  it 'masks contract references for ordinary viewers' do
    expect(described_class.call('CONTRACT-1234', audit_authorized: false)).to eq('CO••••34')
  end

  it 'reveals the full reference only to an audit-authorized caller' do
    expect(described_class.call('CONTRACT-1234', audit_authorized: true)).to eq('CONTRACT-1234')
  end
end
