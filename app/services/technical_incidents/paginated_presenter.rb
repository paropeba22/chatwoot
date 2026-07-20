class TechnicalIncidents::PaginatedPresenter
  def initialize(records)
    @records = records
  end

  def as_json(&)
    {
      payload: @records.map(&),
      meta: {
        current_page: @records.current_page,
        per_page: @records.limit_value,
        total_entries: @records.total_count
      }
    }
  end
end
