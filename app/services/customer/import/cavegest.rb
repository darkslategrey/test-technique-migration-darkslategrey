class Customer::Import::Cavegest < Importer::Base
  N = Importer::Normalization

  KINDS = { "C" => "customer", "F" => "supplier", "P" => "prospect", "R" => "customer" }.freeze

  # Indices de colonnes du fichier CaveGest (2 blocs de colonnes dupliquées : facturation puis livraison).
  COL = {
    reference: 0, last_name: 1, first_name: 2, company_name: 3, address1: 4,
    zip: 5, city: 6, country: 7, email: 8, phone: 9, mobile: 10,
    ship_last_name: 11, ship_first_name: 12, ship_company: 13, ship_address: 14,
    ship_zip: 15, ship_city: 16, ship_country: 17, ship_phone: 18,
    family_code: 19, family_label: 20, price_grid: 21, price_grid_label: 22,
    vat: 23, excise: 24, created_at: 25, inactive: 26
  }.freeze

  def call
    imported    = 0
    no_identity = []

    rows.each do |row|
      reference = N.text(row[COL[:reference]])

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
    country_code = N.country_code(row[COL[:country]])

    customer.assign_attributes(
      reference:         N.text(row[COL[:reference]]),
      last_name:         N.text(row[COL[:last_name]]),
      first_name:        N.text(row[COL[:first_name]]),
      company_name:      N.text(row[COL[:company_name]]),
      address1:          N.text(row[COL[:address1]]),
      city:              N.text(row[COL[:city]]),
      zip:               N.zip(row[COL[:zip]], country_code),
      country_code:      country_code,
      email:             N.text(row[COL[:email]]),
      phone:             N.text(row[COL[:phone]]),
      mobile:            N.text(row[COL[:mobile]]),
      kind:              KINDS[N.text(row[COL[:family_code]])],
      customer_category: N.text(row[COL[:family_label]]),
      price_grid_code:   N.text(row[COL[:price_grid]]),
      vat_number:        N.vat_number(row[COL[:vat]]),
      excise_number:     N.text(row[COL[:excise]])
    )
  end

  def shipping_present?(row)
    row[COL[:ship_address]].present? || row[COL[:ship_city]].present? ||
      row[COL[:ship_zip]].present? || row[COL[:ship_last_name]].present? ||
      row[COL[:ship_company]].present? || row[COL[:ship_first_name]].present?
  end

  def assign_shipping(customer, row)
    country_code = N.country_code(row[COL[:ship_country]])

    customer.assign_attributes(
      shipping_last_name:    N.text(row[COL[:ship_last_name]]),
      shipping_first_name:   N.text(row[COL[:ship_first_name]]),
      shipping_company_name: N.text(row[COL[:ship_company]]),
      shipping_address1:     N.text(row[COL[:ship_address]]),
      shipping_city:         N.text(row[COL[:ship_city]]),
      shipping_zip:          N.zip(row[COL[:ship_zip]], country_code),
      shipping_country_code: country_code,
      shipping_phone:        N.text(row[COL[:ship_phone]])
    )
  end

  def identifiable?(row)
    [COL[:last_name], COL[:first_name], COL[:company_name]].any? do |index|
      N.text(row[index]).present?
    end
  end
end