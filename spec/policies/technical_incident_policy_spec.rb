require 'rails_helper'

RSpec.describe TechnicalIncidentPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let(:incident) { build(:technical_incident, account: account) }

  def context_for(*permissions, administrator: false)
    account_user = instance_double(
      AccountUser,
      administrator?: administrator,
      permissions: permissions.map(&:to_s)
    )
    { user: user, account: account, account_user: account_user }
  end

  permissions :index?, :show?, :options? do
    it { expect(policy).to permit(context_for(:technical_incident_view), incident) }
    it { expect(policy).not_to permit(context_for(:technical_incident_create), incident) }
  end

  permissions :create? do
    it { expect(policy).to permit(context_for(:technical_incident_create), incident) }
  end

  permissions :update? do
    it { expect(policy).to permit(context_for(:technical_incident_update), incident) }
  end

  permissions :update_eta? do
    it { expect(policy).to permit(context_for(:technical_incident_update_eta), incident) }
    it { expect(policy).not_to permit(context_for(:technical_incident_view), incident) }
  end

  permissions :resolve? do
    it { expect(policy).to permit(context_for(:technical_incident_resolve), incident) }
  end

  permissions :archive? do
    it { expect(policy).to permit(context_for(:technical_incident_archive), incident) }
  end

  permissions :history?, :evaluations? do
    it { expect(policy).to permit(context_for(:technical_incident_audit), incident) }
  end

  permissions :destroy?, :transition? do
    it { expect(policy).to permit(context_for(administrator: true), incident) }
  end
end
