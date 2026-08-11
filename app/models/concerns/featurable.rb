module Featurable
  extend ActiveSupport::Concern

  module BulkFeatureSelection
    def selected_feature_flags=(features)
      requested = Array(features).map(&:to_s)
      Featurable::BOOLEAN_FEATURES.each do |feature|
        public_send("#{feature}_enabled=", requested.delete("feature_#{feature}").present?)
      end
      super(requested)
    end
  end

  QUERY_MODE = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze
  BOOLEAN_FEATURES = %w[
    technical_incidents
    conversation_send_to_human_queue
    conversation_return_to_bia
    conversation_operational_buckets
  ].freeze

  FEATURE_LIST = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze

  FEATURES = FEATURE_LIST.each_with_object({}) do |feature, result|
    next if BOOLEAN_FEATURES.include?(feature['name'])

    result[result.keys.size + 1] = "feature_#{feature['name']}".to_sym
  end

  included do
    include FlagShihTzu
    has_flags FEATURES.merge(column: 'feature_flags').merge(QUERY_MODE)
    prepend BulkFeatureSelection

    before_create :enable_default_features
  end

  def enable_features(*names)
    names.each do |name|
      if BOOLEAN_FEATURES.include?(name.to_s)
        public_send("#{name}_enabled=", true)
      else
        send("feature_#{name}=", true)
      end
    end
  end

  def enable_features!(*names)
    enable_features(*names)
    save
  end

  def disable_features(*names)
    names.each do |name|
      if BOOLEAN_FEATURES.include?(name.to_s)
        public_send("#{name}_enabled=", false)
      else
        send("feature_#{name}=", false)
      end
    end
  end

  def disable_features!(*names)
    disable_features(*names)
    save
  end

  def feature_enabled?(name)
    return public_send("#{name}_enabled?") if BOOLEAN_FEATURES.include?(name.to_s)

    send("feature_#{name}?")
  end

  def all_features
    FEATURE_LIST.pluck('name').index_with do |feature_name|
      feature_enabled?(feature_name)
    end
  end

  def enabled_features
    all_features.select { |_feature, enabled| enabled == true }
  end

  def disabled_features
    all_features.select { |_feature, enabled| enabled == false }
  end

  private

  def enable_default_features
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return true if config.blank?

    features_to_enabled = config.value.select { |f| f[:enabled] }.pluck(:name)
    enable_features(*features_to_enabled)
  end
end
