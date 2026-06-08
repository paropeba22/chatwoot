require 'rails_helper'

RSpec.describe Integrations::Sgp::DocumentValidator do
  describe '.normalize' do
    it 'keeps only digits' do
      expect(described_class.normalize('529.982.247-25')).to eq('52998224725')
    end
  end

  describe '.valid?' do
    it 'accepts a valid CPF and CNPJ' do
      expect(described_class.valid?('529.982.247-25')).to be(true)
      expect(described_class.valid?('11.222.333/0001-81')).to be(true)
    end

    it 'rejects invalid lengths, check digits and repeated digits' do
      expect(described_class.valid?('123')).to be(false)
      expect(described_class.valid?('529.982.247-24')).to be(false)
      expect(described_class.valid?('11.222.333/0001-80')).to be(false)
      expect(described_class.valid?('111.111.111-11')).to be(false)
    end
  end
end
