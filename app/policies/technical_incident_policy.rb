class TechnicalIncidentPolicy < ApplicationPolicy
  PERMISSION_MAP = {
    index?: 'technical_incident_view',
    show?: 'technical_incident_view',
    create?: 'technical_incident_create',
    update?: 'technical_incident_update',
    transition?: 'technical_incident_update',
    update_eta?: 'technical_incident_update_eta',
    resolve?: 'technical_incident_resolve',
    archive?: 'technical_incident_archive',
    history?: 'technical_incident_audit',
    conversations?: 'technical_incident_view',
    evaluations?: 'technical_incident_audit',
    destroy?: 'technical_incident_archive'
  }.freeze

  PERMISSION_MAP.each do |method_name, permission|
    define_method(method_name) do
      account_user&.administrator? || account_user&.permissions&.include?(permission)
    end
  end

  def options?
    return true if account_user&.administrator?

    permissions = account_user&.permissions || []
    permissions.intersect?(%w[technical_incident_view technical_incident_create technical_incident_update])
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless account

      scope.where(account_id: account.id)
    end
  end
end
