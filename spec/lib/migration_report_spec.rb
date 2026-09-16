require "spec_helper"

RSpec.describe MigrationReport do
  subject(:report) { described_class.new }

  it "renders counters as a readable non-dev summary" do
    report.count(:customers_imported, 12)
    report.count(:products_imported, 5)

    text = report.to_s
    expect(text).to include("Clients importés : 12")
    expect(text).to include("Produits importés : 5")
  end

  it "renders warnings under a 'à vérifier' section" do
    report.warn(source: "clients", locator: "T00078", message: "aucune identité")

    text = report.to_s
    expect(text).to include("À vérifier")
    expect(text).to include("[clients] T00078: aucune identité")
  end

  it "renders errors under a rejected section" do
    report.error(source: "tarifs", locator: "CUV227", message: "validation échouée")

    text = report.to_s
    expect(text).to include("Rejetés / à corriger")
    expect(text).to include("[tarifs] CUV227: validation échouée")
  end

  it "renders a header on an empty report without error" do
    expect(report.to_s).to include("Rapport de reprise")
  end
end