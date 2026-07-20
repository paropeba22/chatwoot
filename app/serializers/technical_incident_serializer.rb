class TechnicalIncidentSerializer
  def initialize(incident, include_details: false)
    @incident = incident
    @include_details = include_details
  end

  def as_json(*)
    base.merge(@include_details ? details : {})
  end

  private

  def base
    @incident.attributes.slice(
      'id', 'account_id', 'title', 'incident_type', 'status', 'severity', 'priority',
      'problem_types', 'affected_services', 'action', 'starts_at', 'expires_at', 'review_at',
      'estimated_resolution_at', 'notification_version', 'resend_on_next_contact',
      'resolved_at', 'archived_at', 'lock_version', 'conversation_links_count', 'created_at', 'updated_at'
    ).merge(
      created_by: actor(@incident.created_by),
      updated_by: actor(@incident.updated_by),
      resolved_by: actor(@incident.resolved_by)
    )
  end

  def details
    {
      customer_message: @incident.customer_message,
      internal_note: @incident.internal_note,
      scope_groups: serialized_scope_groups,
      conflicts: TechnicalIncidents::ConflictService.new(@incident).call,
      metrics: metrics
    }
  end

  def serialized_scope_groups
    @incident.scope_groups.map do |group|
      {
        id: group.id,
        position: group.position,
        criteria: group.criteria.map { |criterion| serialized_criterion(criterion) }
      }
    end
  end

  def serialized_criterion(criterion)
    criterion.attributes.slice('id', 'criterion_type', 'operator', 'values')
  end

  def metrics
    evaluation_metrics.merge(delivery_metrics).merge(
      conversations: @incident.conversation_links_count,
      deliveries: @incident.deliveries.count
    )
  end

  def evaluation_metrics
    {
      evaluations: @incident.evaluations.count,
      matched: @incident.evaluations.where(status: %w[matched accepted]).count,
      duplicates_prevented: @incident.evaluations.where(status: 'duplicate').count,
      false_positives: @incident.evaluations.where(feedback: 'false_positive').count,
      false_negatives: @incident.evaluations.where(feedback: 'false_negative').count
    }
  end

  def delivery_metrics
    {
      delivered: @incident.deliveries.where(transport_state: %w[delivered not_required]).count,
      outbox_pending: @incident.deliveries.where(outbox_state: %w[pending processing retry]).count,
      outbox_failed: @incident.deliveries.where(outbox_state: 'failed_terminal').count
    }
  end

  def actor(user)
    user && { id: user.id, name: user.name }
  end
end
