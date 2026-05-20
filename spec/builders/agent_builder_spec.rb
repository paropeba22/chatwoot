require 'rails_helper'

RSpec.describe AgentBuilder, type: :model do
  subject(:agent_builder) { described_class.new(params) }

  let(:account) { create(:account) }
  let!(:current_user) { create(:user, account: account) }
  let(:email) { 'test@example.com' }
  let(:name) { 'Test User' }
  let(:role) { 'agent' }
  let(:availability) { 'offline' }
  let(:auto_offline) { false }
  let(:password) { 'TempPass1!' }
  let(:password_confirmation) { 'TempPass1!' }
  let(:params) do
    {
      email: email,
      name: name,
      password: password,
      password_confirmation: password_confirmation,
      inviter: current_user,
      account: account,
      role: role,
      availability: availability,
      auto_offline: auto_offline
    }
  end

  describe '#perform' do
    context 'when user does not exist' do
      it 'creates a new user' do
        expect { agent_builder.perform }.to change(User, :count).by(1)
      end

      it 'creates a new account user' do
        expect { agent_builder.perform }.to change(AccountUser, :count).by(1)
      end

      it 'returns a user' do
        expect(agent_builder.perform).to be_a(User)
      end
    end

    context 'when user exists' do
      let!(:existing_user) do
        create(:user, email: email, password: 'ExistingPass1!', skip_confirmation: false)
      end

      it 'does not create a new user' do
        expect { agent_builder.perform }.not_to change(User, :count)
      end

      it 'creates a new account user' do
        expect { agent_builder.perform }.to change(AccountUser, :count).by(1)
      end

      it 'does not override password for existing users' do
        agent_builder.perform
        expect(existing_user.reload.valid_password?('ExistingPass1!')).to be(true)
      end
    end

    context 'when only email is provided' do
      let(:params) { { email: email, inviter: current_user, account: account } }

      it 'creates a user with default values' do
        user = agent_builder.perform
        expect(user.name).to eq('')
        expect(AccountUser.find_by(user: user).role).to eq('agent')
      end
    end

    context 'when a temporary password is generated' do
      let(:password) { nil }
      let(:password_confirmation) { nil }

      it 'sets a temporary password for the user' do
        with_modified_env AGENT_AUTO_CONFIRM_ON_CREATE: 'false' do
          user = agent_builder.perform
          expect(user.encrypted_password).not_to be_empty
        end
      end
    end

    context 'when agent auto confirm flag is enabled' do
      it 'confirms a newly created user' do
        with_modified_env AGENT_AUTO_CONFIRM_ON_CREATE: 'true' do
          user = agent_builder.perform
          expect(user.reload).to be_confirmed
        end
      end

      it 'confirms an existing pending user' do
        with_modified_env AGENT_AUTO_CONFIRM_ON_CREATE: 'true' do
          existing_user = create(:user, email: email, skip_confirmation: false)
          described_class.new(params).perform
          expect(existing_user.reload).to be_confirmed
        end
      end

      it 'requires password for newly created users' do
        with_modified_env AGENT_AUTO_CONFIRM_ON_CREATE: 'true' do
          builder = described_class.new(params.merge(password: nil, password_confirmation: nil))
          expect { builder.perform }.to raise_error(ActiveRecord::RecordInvalid)
        end
      end
    end

    context 'when agent auto confirm flag is disabled' do
      it 'keeps a newly created user unconfirmed' do
        with_modified_env AGENT_AUTO_CONFIRM_ON_CREATE: 'false' do
          user = agent_builder.perform
          expect(user.reload).not_to be_confirmed
        end
      end
    end
  end
end
