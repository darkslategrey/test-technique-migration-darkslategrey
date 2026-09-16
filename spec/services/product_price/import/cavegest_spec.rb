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
end