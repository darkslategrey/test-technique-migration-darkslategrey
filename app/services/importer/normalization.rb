module Importer::Normalization
  module_function

  def text(value)
    return nil if value.nil?

    str = value.to_s.strip
    str unless str.empty?
  end

  def zip(value, country_code = "FR")
    return nil if value.nil?

    digits = value.to_s.gsub(/[^\d]/, "")
    return nil if digits.empty?

    padding = country_code.to_s.casecmp?("BE") ? 4 : 5
    digits.rjust(padding, "0")
  end

  KNOWN_COUNTRY_CODES = %w[FR BE DE].freeze

  def country_code(value)
    return nil if value.nil?

    key = value.to_s.strip
    return nil if key.empty?

    code = key.casecmp?("Allemagne") ? "DE" : key[0, 2].upcase
    KNOWN_COUNTRY_CODES.include?(code) ? code : nil
  end

  def decimal(value)
    return nil if value.nil?

    str = value.to_s.strip
    return nil if str.empty? || str.casecmp?("N/C")

    normalized = str
      .gsub(/\u00a0|\u202f/, "")
      .gsub(/EUR|\$/i, "")
      .gsub("%", "")
      .gsub(/\s+/, "")
      .gsub(",", ".")

    return nil unless normalized.match?(/\d/)

    normalized.to_f
  end
end
