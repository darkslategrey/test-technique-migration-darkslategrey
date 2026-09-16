class ProductPrice::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  COLUMN_SEP = ";".freeze
  GRID_CODES = %w[DEPC CHR EXPO PART SALON].freeze

  ENCODING = Encoding::ISO_8859_1

  # Taux de TVA -> coefficient de conversion TTC vers HT (grille EXPO).
  VAT_COEFFICIENTS = { 20.0 => 1.2, 5.5 => 1.055 }.freeze

  def call
    imported = 0
    rejected = 0

    data_rows.each do |row|
      reference = N.text(row[0])

      # Une référence partagée par plusieurs lignes est une donnée source à
      # faire trancher par le client : on rejette explicitement, sans inventer
      # d'identifiant ni écraser silencieusement.
      if conflict_references.include?(reference)
        report.count(:product_conflict)
        report.error(source: "tarifs", locator: reference,
                     message: "référence partagée par plusieurs lignes — à corriger côté client",
                     details: row_details(row))
        rejected += 1
        next
      end

      product = upsert_product(reference, row)
      import_prices(product, row)
      report.count(:products_imported)
      imported += 1
    rescue ActiveRecord::RecordInvalid => e
      report.error(source: "tarifs", locator: reference, message: e.message)
      report.count(:products_rejected)
      rejected += 1
    end

    puts "#{imported} produits importés, #{rejected} rejetés (dont #{conflict_references.size} références partagées)"
  end

  private

  def data_rows
    @data_rows ||= begin
      rows = CSV.read(path, encoding: ENCODING, col_sep: COLUMN_SEP)
      header_index = rows.index { |r| r[0] == "Ref" }
      raise ArgumentError, "En-tête 'Ref' introuvable dans le fichier #{path}" unless header_index
      @header_row = rows[header_index]
      raw = rows[(header_index + 1)..]
      raw.reject do |r|
        structural?(r) || empty_line?(r)
      end
    end
  end

  def header_row
    @header_row || (data_rows; @header_row)
  end

  # Index dynamique des colonnes de grilles, dérivé de l'en-tête réel.
  def grid_index
    @grid_index ||= GRID_CODES.to_h do |code|
      idx = header_row.index(code)
      raise ArgumentError, "Colonne '#{code}' introuvable dans l'en-tête" unless idx
      [code, idx]
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

  # Tous les numéros de référence qui apparaissent plus d'une fois dans
  # l'export. Ces doublons constituent une ambigüité que l'import ne doit pas
  # trancher seul : on les écarte et on les escalade.
  def conflict_references
    @conflict_references ||= data_rows
      .each_with_object(Hash.new(0)) do |row, counts|
        ref = N.text(row[0])
        counts[ref] += 1 if ref
      end
      .select { |_ref, count| count > 1 }
      .keys
  end

  # Rend une ligne du fichier lisible dans le rapport (référence, nom, volume,
  # TVA, stocks et tarifs).
  def row_details(row)
    {
      reference: to_utf8(N.text(row[0])),
      name:      to_utf8(N.text(row[1])),
      volume:    to_utf8(N.text(row[2])),
      vat_rate:  to_utf8(N.text(row[4])),
      stock:     N.decimal(row[10]).to_i,
      prices:    GRID_CODES.to_h { |g| [g, N.decimal(row[grid_index[g]])] }
    }
  end

  def to_utf8(value)
    return nil if value.nil?

    value.encode("UTF-8", invalid: :replace, undef: :replace)
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
      value = N.decimal(row[grid_index[grid_code]])
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
