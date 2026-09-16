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

      reference = resolve_reference(base_reference, row)
      product   = upsert_product(reference, row)
      import_prices(product, row)
      report.count(:products_imported)
      imported += 1
    rescue ActiveRecord::RecordInvalid => e
      report.error(source: "tarifs", locator: base_reference, message: e.message)
      report.count(:products_rejected)
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
        structural?(r) || empty_line?(r)
      end
    end
  end

  def structural?(row)
    row[0].to_s.start_with?("---", "SOUS-TOTAL")
  end

  def empty_line?(row)
    row[0].to_s.strip.empty?
  end

  def row_volume_ml(row)
    volume_ml(row[2])
  end

  def row_occurrences
    @row_occurrences ||= data_rows.each_with_object(Hash.new(0)) do |row, counts|
      ref = N.text(row[0])
      counts[ref] += 1 if ref
    end
  end

  # Une référence peut être dupliquée dans l'export (ex. HAU214 apparaît 2x,
  # parfois avec le même contenant). On suffixe par un index d'occurrence stable
  # (ex. CUV227-2, HAU214-2) pour garantir une référence unique par ligne,
  # retrouvée au re-run -> l'import est idempotent.
  def resolve_reference(base_reference, row)
    return base_reference if row_occurrences[base_reference] <= 1

    occurrence_counter[base_reference] += 1
    "#{base_reference}-#{occurrence_counter[base_reference]}"
  end

  def occurrence_counter
    @occurrence_counter ||= Hash.new(0)
  end

  def upsert_product(reference, row)
    product = Product.find_or_initialize_by(reference: reference)
    product.assign_attributes(
      name:      N.text(row[1]),
      color:     N.text(row[3]),
      volume_ml: row_volume_ml(row),
      vat_rate:  N.decimal(row[4]),
      stock:     N.decimal(row[10]).to_i
    )
    product.save!
    product
  end

  def import_prices(product, row)
    GRID_CODES.each do |grid_code|
      value = N.decimal(row[GRID_INDEX[grid_code]])
      next if value.nil? || value.zero?

      coefficient = VAT_COEFFICIENTS.fetch(product.vat_rate.to_f, 1.0)
      amount = grid_code == "EXPO" ? value / coefficient : value

      price = ProductPrice.find_or_initialize_by(product: product, grid_code: grid_code)
      price.amount_ht = amount.round(2)
      price.save!
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
