class ProductPrice::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  COLUMN_SEP = ";".freeze
  GRID_CODES = %w[DEPC CHR EXPO PART SALON].freeze
  GRID_INDEX = { "DEPC" => 5, "CHR" => 6, "EXPO" => 7, "PART" => 8, "SALON" => 9 }.freeze

  ENCODING = Encoding::ISO_8859_1

  # Taux de TVA -> coefficient de conversion TTC vers HT (grille EXPO).
  VAT_COEFFICIENTS = { 20.0 => 1.2, 5.5 => 1.055 }.freeze

  def call
    imported = 0
    skipped  = 0

    data_rows.each do |row|
      base_reference = N.text(row[0])
      next if base_reference.nil?

      reference = unique_reference(base_reference, row)
      product   = build_product(reference, row)
      product.save!
      import_prices(product, row)
      imported += 1
    rescue ActiveRecord::RecordInvalid => e
      report.error(source: "tarifs", locator: base_reference, message: e.message)
      skipped += 1
    end

    puts "#{imported} produits importés, #{skipped} rejetés"
  end

  private

  def data_rows
    @data_rows ||= begin
      rows = CSV.read(path, encoding: ENCODING, col_sep: COLUMN_SEP)
      header_index = rows.index { |r| r[0] == "Ref" }
      raw = header_index ? rows[(header_index + 1)..] : []
      raw.reject do |r|
        r[0].to_s.start_with?("---", "SOUS-TOTAL") || r[0].to_s.strip.empty?
      end
    end
  end

  def row_volume_ml(row)
    volume_ml(row[2])
  end

  # La référence peut être dupliquée dans l'export avec un contenant différent
  # (ex. CUV227 en Bouteille puis en Magnum). On suffixe la 2e occurrence.
  def unique_reference(base_reference, row)
    return base_reference unless Product.exists?(reference: base_reference)

    suffix = row_volume_ml(row) ? "#{row_volume_ml(row)}ML" : "NOVOL"
    "#{base_reference}-#{suffix}"
  end

  def build_product(reference, row)
    Product.new(
      reference: reference,
      name:      N.text(row[1]),
      color:     N.text(row[3]),
      volume_ml: row_volume_ml(row),
      vat_rate:  N.decimal(row[4]),
      stock:     N.decimal(row[10]).to_i
    )
  end

  def import_prices(product, row)
    GRID_CODES.each do |grid_code|
      value = N.decimal(row[GRID_INDEX[grid_code]])
      next if value.nil? || value.zero?

      coefficient = VAT_COEFFICIENTS.fetch(product.vat_rate.to_f, 1.0)
      amount = grid_code == "EXPO" ? value / coefficient : value

      ProductPrice.create!(
        product:   product,
        grid_code: grid_code,
        amount_ht: amount.round(2)
      )
    end
  end

  # Volume exprimé en centilitres dans le fichier (Bouteille 75, Magnum 150,
  # BIB 300...), converti en millilitres (x10). Carton / 6 x 75 / vide : nil.
  def volume_ml(value)
    text = value.to_s.strip
    return nil if text.empty?

    return nil if text =~ /Carton|^\d+\s*x\s*\d+/

    match = text.match(/- (\d+(?:\.\d+)?)/)
    return nil unless match

    (match[1].to_f * 10).to_i
  end
end