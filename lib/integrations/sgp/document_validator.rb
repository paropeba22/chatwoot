class Integrations::Sgp::DocumentValidator
  class << self
    def normalize(value)
      value.to_s.gsub(/\D/, '')
    end

    def valid?(value)
      document = normalize(value)
      return false unless [11, 14].include?(document.length)
      return false if document.chars.uniq.one?

      document.length == 11 ? valid_cpf?(document) : valid_cnpj?(document)
    end

    private

    def valid_cpf?(document)
      digits = document.chars.map(&:to_i)
      first = cpf_digit(digits.first(9), 10)
      second = cpf_digit(digits.first(9) + [first], 11)

      digits.last(2) == [first, second]
    end

    def cpf_digit(digits, weight)
      remainder = digits.sum do |digit|
        product = digit * weight
        weight -= 1
        product
      end % 11
      remainder < 2 ? 0 : 11 - remainder
    end

    def valid_cnpj?(document)
      digits = document.chars.map(&:to_i)
      first = cnpj_digit(digits.first(12), [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])
      second = cnpj_digit(digits.first(12) + [first], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])

      digits.last(2) == [first, second]
    end

    def cnpj_digit(digits, weights)
      remainder = digits.zip(weights).sum { |digit, weight| digit * weight } % 11
      remainder < 2 ? 0 : 11 - remainder
    end
  end
end
