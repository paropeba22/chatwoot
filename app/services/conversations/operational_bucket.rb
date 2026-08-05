class Conversations::OperationalBucket
  BUCKETS = %w[mine human_queue bia].freeze
  BOT_LABEL = 'bot-bia'.freeze
  HUMAN_QUEUE_LABEL = 'aguardando-humano'.freeze
  SESSION_KEYS = %w[bia_automation_state bia_session_generation].freeze

  Result = Struct.new(:bucket, :reason, :inconsistent, keyword_init: true)

  class << self
    def scope(relation, bucket:, current_user:)
      raise ArgumentError, 'invalid_operational_bucket' unless BUCKETS.include?(bucket)

      send("#{bucket}_scope", relation, current_user)
    end

    def counts(relation, current_user:)
      BUCKETS.index_with { |bucket| scope(relation, bucket: bucket, current_user: current_user).count }
    end

    private

    def mine_scope(relation, current_user)
      relation.where(status: :open, assignee_id: current_user.id)
    end

    def human_queue_scope(relation, _current_user)
      relation.where(status: :open, assignee_id: nil, assignee_agent_bot_id: nil)
              .where(id: tagged_ids(relation, HUMAN_QUEUE_LABEL))
    end

    def bia_scope(relation, _current_user)
      relation.where(status: :open, assignee_id: nil, assignee_agent_bot_id: nil)
              .where(id: tagged_ids(relation, BOT_LABEL))
              .where.not(id: tagged_ids(relation, HUMAN_QUEUE_LABEL))
              .where(strict_state_sql, state: 'active')
    end

    def tagged_ids(relation, label)
      relation.tagged_with(label).reselect(:id)
    end

    def strict_state_sql
      <<~SQL.squish
        NOT (conversations.custom_attributes ?| ARRAY['bia_automation_state', 'bia_session_generation'])
        OR conversations.custom_attributes ->> 'bia_automation_state' = :state
      SQL
    end
  end

  def initialize(conversation, current_user: nil)
    @conversation = conversation
    @current_user = current_user
  end

  def call
    return result('mine', 'human_assignee_precedence') if mine?
    return result('human_queue', 'human_queue_label_precedence') if human_queue?
    return result('bia', strict_session? ? 'strict_bia_state' : 'legacy_bia_state') if bia?

    result(nil, 'unclassified')
  end

  private

  attr_reader :conversation, :current_user

  def mine?
    conversation.open? && conversation.assignee_id.present? && (current_user.nil? || conversation.assignee_id == current_user.id)
  end

  def human_queue?
    conversation.open? && conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil? && labels.include?(HUMAN_QUEUE_LABEL)
  end

  def bia?
    conversation.open? && conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil? &&
      labels.include?(BOT_LABEL) && labels.exclude?(HUMAN_QUEUE_LABEL) && (!strict_session? || automation_state == 'active')
  end

  def strict_session?
    SESSION_KEYS.any? { |key| attributes.key?(key) }
  end

  def inconsistent?
    (labels.include?(BOT_LABEL) && labels.include?(HUMAN_QUEUE_LABEL)) ||
      (conversation.assignee_id.present? && (labels.include?(BOT_LABEL) || automation_state == 'active')) ||
      (automation_state == 'paused_human' && labels.include?(BOT_LABEL))
  end

  def result(bucket, reason)
    Result.new(bucket: bucket, reason: reason, inconsistent: inconsistent?)
  end

  def labels
    @labels ||= conversation.cached_label_list_array
  end

  def attributes
    @attributes ||= conversation.custom_attributes || {}
  end

  def automation_state
    attributes['bia_automation_state'].to_s
  end
end
