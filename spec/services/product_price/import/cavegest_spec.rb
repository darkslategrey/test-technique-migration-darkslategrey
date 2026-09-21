require "spec_helper"

RSpec.describe ProductPrice::Import::Cavegest do
  let(:path) { data_path("export_tarifs_cavegest.csv") }
  let(:importer) { described_class.new(path) }

  before { importer.call }

  it "imports the real products from the file" do
    # 113 produits réels + 6 doublons traités => ~
    expect(Product.count).to be > 100
  end

  it "reads prices with French decimal commas" do
    product = Product.find_by(reference: "LANM3")
    price = product.product_prices.find_by(grid_code: "DEPC")
    expect(price.amount_ht).to eq(13.32)
  end

  it "converts the EXPO grid from TTC to HT based on the product VAT" do
    # LANM3 : TVA 20%, EXPO 15,98 TTC -> 15,98 / 1,2 = 13.3166...
    product = Product.find_by(reference: "LANM3")
    expo = product.product_prices.find_by(grid_code: "EXPO")
    expect(expo.amount_ht).to be_within(0.01).of(15.98 / 1.2)
  end

  it "applies a 5.5% coefficient for products at 5.5% VAT" do
    product = Product.find_by(reference: "TRA231")
    expo = product.product_prices.find_by(grid_code: "EXPO")
    expect(expo.amount_ht).to be_within(0.01).of(12.30 / 1.055)
  end

  it "does not create a zero-price grid when the column is empty" do
    product = Product.find_by(reference: "LANM3")
    # SALON est vide pour LANM3 -> pas de ProductPrice SALON à 0
    expect(product.product_prices.exists?(grid_code: "SALON")).to be false
  end

  it "sets the volume from the container" do
    product = Product.find_by(reference: "LANM3")
    expect(product.volume_ml).to eq(3000) # BIB - 300.0
  end

  it "does not compute a bogus volume for cartons or non-volume containers" do
    product = Product.find_by(reference: "TRA195") # Carton 6
    expect(product.volume_ml).to be_nil
  end

  it "normalizes tv the VAT rate" do
    product = Product.find_by(reference: "LANM3")
    expect(product.vat_rate).to eq(20.0)
  end

  it "rejects products sharing a duplicate reference" do
    # CUV227, HAU214, ... apparaissent plusieurs fois : aucun produit n'est créé.
    %w[CUV227 CUV228 HAU214 LES194 TER232 VIENM6].each do |ref|
      expect(Product.find_by(reference: ref)).to be_nil
      expect(ProductPrice.where(grid_code: nil).count).to eq(0)
    end
  end

  it "counts duplicate-reference conflicts in the report" do
    report = MigrationReport.new
    described_class.new(path, report: report).call

    expect(report.counters[:product_conflict]).to eq(12)
    expect(report.warnings.size + report.errors.size).to be >= 12
  end

  context "with header validation" do
    require "tempfile"

    let(:base_header) { %w[Ref Désignation Contenant Couleur TVA DEPC CHR EXPO PART SALON Stock] }

    def write_tarifs_csv(header, rows)
      file = Tempfile.new(["tarifs", ".csv"])
      File.open(file.path, "w:ISO-8859-1") do |f|
        f.puts "CaveGest 4.2 - Export test".encode("ISO-8859-1")
        f.puts ""
        f.puts header.join(";").encode("ISO-8859-1")
        rows.each { |r| f.puts r.join(";").encode("ISO-8859-1") }
      end
      file
    end

    it "raises an explicit error when a base column is missing" do
      header = base_header - ["Stock"]
      file = write_tarifs_csv(header, [["TST001", "Vin Test", "Bouteille - 75.0", "Rouge", "20", "10,00", "20,00", "", "", ""]])
      expect { described_class.new(file.path).call }.to raise_error(ArgumentError, /Stock/)
      file.close!
    end

    it "raises an explicit error when a base column is renamed" do
      header = base_header.map { |h| h == "Désignation" ? "Designation" : h }
      file = write_tarifs_csv(header, [["TST001", "Vin Test", "Bouteille - 75.0", "Rouge", "20", "10,00", "20,00", "", "", "", "5"]])
      expect { described_class.new(file.path).call }.to raise_error(ArgumentError, /Désignation/)
      file.close!
    end

    it "raises an explicit error when a grid column is missing" do
      header = base_header - ["DEPC"]
      file = write_tarifs_csv(header, [["TST001", "Vin Test", "Bouteille - 75.0", "Rouge", "20", "20,00", "", "", "", "5"]])
      expect { described_class.new(file.path).call }.to raise_error(ArgumentError, /DEPC/)
      file.close!
    end

    it "maps columns by header name when grids are reordered" do
      header = ["Ref", "Désignation", "Contenant", "Couleur", "TVA", "CHR", "DEPC", "EXPO", "PART", "SALON", "Stock"]
      row = ["TST999", "Vin Test", "Bouteille - 75.0", "Rouge", "20", "20,00", "10,00", "", "", "", "5"]
      file = write_tarifs_csv(header, [row])
      described_class.new(file.path).call

      product = Product.find_by(reference: "TST999")
      expect(product).not_to be_nil
      expect(product.product_prices.find_by(grid_code: "DEPC").amount_ht).to eq(10.0)
      expect(product.product_prices.find_by(grid_code: "CHR").amount_ht).to eq(20.0)
      file.close!
    end
  end
end