json.status @transition_status
json.reason_code @reason_code
json.transition_id @transition&.id
json.conversation do
  json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: @conversation
end
