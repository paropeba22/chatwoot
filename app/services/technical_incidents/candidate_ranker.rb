class TechnicalIncidents::CandidateRanker
  SEVERITY_RANK = { 'informational' => 0, 'minor' => 1, 'major' => 2, 'critical' => 3 }.freeze

  def self.sort(matches)
    matches.sort_by do |match|
      incident = match.fetch(:incident)
      [-match.fetch(:specificity), -service_specificity(incident), -incident.priority, -SEVERITY_RANK.fetch(incident.severity)]
    end
  end

  def self.ambiguous?(matches)
    return false if matches.length < 2

    first = ranking_key(matches[0])
    second = ranking_key(matches[1])
    first == second
  end

  def self.ranking_key(match)
    incident = match.fetch(:incident)
    [
      match.fetch(:specificity),
      service_specificity(incident),
      incident.priority,
      SEVERITY_RANK.fetch(incident.severity)
    ]
  end

  def self.service_specificity(incident)
    incident.service_specific_scope? ? 1 : 0
  end
end
