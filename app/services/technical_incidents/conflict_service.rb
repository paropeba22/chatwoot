class TechnicalIncidents::ConflictService
  def initialize(incident)
    @incident = incident
  end

  def call
    candidates.filter_map do |other|
      reasons = conflict_reasons(other)
      next if reasons.empty?

      { incident_id: other.id, title: other.title, severity: other.severity, reasons: reasons }
    end
  end

  private

  def candidates
    @incident.account.technical_incidents.intercepting.where.not(id: @incident.id).includes(scope_groups: :criteria)
  end

  def semantic_overlap?(other)
    other.problem_types.intersect?(@incident.problem_types) && service_overlap?(other)
  end

  def conflict_reasons(other)
    [].tap do |reasons|
      reasons << 'compatible_general_active' if other.general_scope? && semantic_overlap?(other)
      reasons << 'same_service' if other.affected_services.intersect?(@incident.affected_services)
      reasons << 'same_problem_type' if other.problem_types.intersect?(@incident.problem_types)
      reasons << 'overlapping_scope' if scope_fingerprints(other).intersect?(scope_fingerprints(@incident))
    end
  end

  def service_overlap?(other)
    other.affected_services.empty? || @incident.affected_services.empty? ||
      other.affected_services.intersect?(@incident.affected_services)
  end

  def scope_fingerprints(incident)
    incident.scope_groups.flat_map do |group|
      group.criteria.map { |criterion| [criterion.criterion_type, criterion.values].to_json }
    end.to_set
  end
end
