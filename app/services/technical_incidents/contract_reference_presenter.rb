class TechnicalIncidents::ContractReferencePresenter
  def self.call(reference, audit_authorized:)
    value = reference.to_s
    return value if audit_authorized
    return '' if value.blank?

    "#{value.first(2)}••••#{value.last(2)}"
  end
end
