require "spec_helper"

RSpec.describe Importer::Audit do
  let(:audit) { described_class.new }

  describe "#call" do
    it "returns a report object respondable to to_s" do
      expect(audit.call).to respond_to(:to_s)
    end

    it "is printed by the rake task without error" do
      expect { audit.to_s }.not_to raise_error
    end
  end

  describe "counts" do
    it "reports the number of customers, products and prices" do
      expect(audit.to_s).to include("Clients :")
      expect(audit.to_s).to include("Produits :")
      expect(audit.to_s).to include("Prix :")
    end
  end
end