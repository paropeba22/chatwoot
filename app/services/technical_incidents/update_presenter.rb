class TechnicalIncidents::UpdatePresenter
  def initialize(update)
    @update = update
  end

  def as_json
    {
      id: @update.id,
      action: @update.action,
      origin: @update.origin,
      actor: actor_payload,
      changeset: @update.changeset,
      request_id: @update.request_id,
      created_at: @update.created_at
    }
  end

  private

  def actor_payload
    return unless @update.actor

    { id: @update.actor.id, type: @update.actor_type, name: @update.actor.try(:name) }
  end
end
