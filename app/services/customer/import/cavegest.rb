class Customer::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  KINDS = { "C" => "customer", "F" => "supplier", "P" => "prospect", "R" => "customer" }.freeze

  # En-têtes attendus dans l'ordre du fichier Excel CaveGest. La validation par nom évite les corruptions silencieuses
  # en cas de changement d'ordre ou de renommage de colonnes.
  EXPECTED_HEADERS = [
    "Code", "Nom", "Prénom", "Libellé", "Adresse", "Code postal", "Ville", "Pays",
    "EMail", "Téléphone 1", "Téléphone 2", "Nom", "Prénom", "Libellé", "Adresse",
    "Code postal", "Ville", "Pays", "Téléphone 1", "Code famille client",
    "Libellé famille client", "Code categ tarif", "Libellé categ tarif",
    "Numéro de TVA", "Numéro d Accise", "Date de création", "Inutilisable"
  ].freeze

  LOGICAL_KEYS = %i[
    reference last_name first_name company_name address1 zip city country email phone mobile
    ship_last_name ship_first_name ship_company ship_address ship_zip ship_city ship_country ship_phone
    family_code family_label price_grid price_grid_label vat excise created_at inactive
  ].freeze

  def call
    imported    = 0
    no_identity = []

    rows.each do |row|
      reference = N.text(row[col_index(:reference)])

      # Ligne de total : ignorée silencieusement.
      next if reference == "TOTAL"

      # Lignes vides (sans référence) : ignorées silencieusement.
      next if reference.nil?

      # Ligne avec référence mais sans identité : rejet explicite plutôt qu'échec silencieux.
      unless identifiable?(row)
        no_identity << reference
        next
      end

      customer = find_or_initialize(reference)
      assign_billing(customer, row)

      if shipping_present?(row)
        assign_shipping(customer, row)
        customer.use_billing_address = false
      end

      customer.save!
      report.count(:customers_imported)
      imported += 1
    end

    report.count(:customers_skipped, no_identity.size)
    report.warn(source: "clients", locator: no_identity.join(", "), message: "sans identité (nom, prénom ou raison sociale)") unless no_identity.empty?

    puts "#{imported} clients importés"
  end

  private

  def rows
    ensure_mapping!
    @rows ||= begin
      parsed = sheet.parse
      parsed.drop(1)
    end
  end

  def sheet
    @sheet ||= Roo::Excelx.new(path).sheet(0)
  end

  def find_or_initialize(reference)
    Customer.find_or_initialize_by(reference: reference)
  end

  def assign_billing(customer, row)
    country_code = N.country_code(row[col_index(:country)])

    customer.assign_attributes(
      reference:         N.text(row[col_index(:reference)]),
      last_name:         N.text(row[col_index(:last_name)]),
      first_name:        N.text(row[col_index(:first_name)]),
      company_name:      N.text(row[col_index(:company_name)]),
      address1:          N.text(row[col_index(:address1)]),
      city:              N.text(row[col_index(:city)]),
      zip:               N.zip(row[col_index(:zip)], country_code),
      country_code:      country_code,
      email:             N.text(row[col_index(:email)]),
      phone:             N.text(row[col_index(:phone)]),
      mobile:            N.text(row[col_index(:mobile)]),
      kind:              KINDS[N.text(row[col_index(:family_code)])],
      customer_category: N.text(row[col_index(:family_label)]),
      price_grid_code:   N.text(row[col_index(:price_grid)]),
      vat_number:        N.vat_number(row[col_index(:vat)]),
      excise_number:     N.text(row[col_index(:excise)])
    )
  end

  def shipping_present?(row)
    row[col_index(:ship_address)].present? || row[col_index(:ship_city)].present? ||
      row[col_index(:ship_zip)].present? || row[col_index(:ship_last_name)].present? ||
      row[col_index(:ship_company)].present? || row[col_index(:ship_first_name)].present?
  end

  def assign_shipping(customer, row)
    country_code = N.country_code(row[col_index(:ship_country)])

    customer.assign_attributes(
      shipping_last_name:    N.text(row[col_index(:ship_last_name)]),
      shipping_first_name:   N.text(row[col_index(:ship_first_name)]),
      shipping_company_name: N.text(row[col_index(:ship_company)]),
      shipping_address1:     N.text(row[col_index(:ship_address)]),
      shipping_city:         N.text(row[col_index(:ship_city)]),
      shipping_zip:          N.zip(row[col_index(:ship_zip)], country_code),
      shipping_country_code: country_code,
      shipping_phone:        N.text(row[col_index(:ship_phone)])
    )
  end

  def identifiable?(row)
    [:last_name, :first_name, :company_name].any? do |key|
      N.text(row[col_index(key)]).present?
    end
  end

  def ensure_mapping!
    @column_map ||= build_column_map
  end

  def build_column_map
    actual = sheet.row(1).map { |h| normalize_header(h) }
    expected = EXPECTED_HEADERS.map { |h| normalize_header(h) }

    mismatches = expected.each_with_index.select { |exp, i| actual[i] != exp }
    unless mismatches.empty?
      details = mismatches.map { |exp, i| "col #{i + 1}: attendu '#{exp}', trouvé '#{actual[i]}'" }.join("; ")
      raise ArgumentError, "En-têtes clients CaveGest inattendus: #{details}"
    end

    LOGICAL_KEYS.each_with_object({}) { |key, map| map[key] = LOGICAL_KEYS.index(key) }
  end

  def normalize_header(h)
    h.to_s.strip.gsub(/\u00A0/, ' ').gsub(/\s+/, ' ')
  end

  def col_index(key)
    @column_map[key]
  end
end