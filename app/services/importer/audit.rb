class Importer::Audit
  def self.call = new.call

  def call
    {
      compteurs: {
        customers:      Customer.count,
        products:       Product.count,
        product_prices: ProductPrice.count
      },
      a_verifier: checks.filter_map(&:call)
    }
  end

  def to_s
    report = call
    lines = []
    lines << "===== Audit de la reprise ====="
    lines << "Clients : #{report[:compteurs][:customers]}"
    lines << "Produits : #{report[:compteurs][:products]}"
    lines << "Prix : #{report[:compteurs][:product_prices]}"
    lines << ""
    lines << "--- À vérifier ---"
    if report[:a_verifier].empty?
      lines << "Aucune anomalie détectée."
    else
      report[:a_verifier].each { |item| lines << "- #{item}" }
    end
    lines.join("\n")
  end

  private

  def checks
    [
      -> { unknown_grids_check },
      -> { count_check("Produits sans aucun prix",
           Product.left_joins(:product_prices).where(product_prices: { id: nil }).count) },
      -> { count_check("Prix à 0", ProductPrice.where(amount_ht: 0).count) },
      -> { count_check("Stocks négatifs", Product.where("stock < 0").count) },
      -> { count_check("Clients sans email", Customer.where(email: [nil, ""]).count) },
      -> { count_check("Clients avec code pays non standard",
           Customer.where.not(country_code: [nil, "FR", "BE", "DE"]).count) },
      -> { count_check("Codes postaux non-5 chiffres (hors BE)",
           Customer.where.not(country_code: "BE").where.not(zip: nil)
                   .select { |c| c.zip !~ /\A\d{5}\z/ }.size) }
    ]
  end

  def count_check(label, count)
    return nil if count.zero?

    "#{label} : #{count}"
  end

  def unknown_grids_check
    bad = Customer.where.not(price_grid_code: nil)
                  .where.not(price_grid_code: grid_codes)
                  .group(:price_grid_code)
    return nil if bad.count.empty?

    lines = ["Clients avec une grille tarifaire inconnue (absente des tarifs) :"]
    bad.count.each do |grid, count|
      refs = Customer.where(price_grid_code: grid).order(:reference).pluck(:reference)
      lines << "  #{grid} (#{count}) : #{refs.join(", ")}"
    end
    lines.join("\n")
  end

  def grid_codes
    ProductPrice::Import::Cavegest::GRID_CODES
  end
end