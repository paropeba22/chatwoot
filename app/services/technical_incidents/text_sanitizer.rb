class TechnicalIncidents::TextSanitizer
  CONTROL_CHARACTERS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/

  def self.call(value)
    return if value.nil?

    value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
         .gsub(CONTROL_CHARACTERS, '')
         .strip
  end
end
