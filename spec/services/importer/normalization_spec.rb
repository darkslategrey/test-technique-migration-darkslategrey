require "spec_helper"

RSpec.describe Importer::Normalization do
  describe ".text" do
    it "returns nil for nil, empty and blank strings" do
      expect(described_class.text(nil)).to be_nil
      expect(described_class.text("")).to be_nil
      expect(described_class.text("   ")).to be_nil
    end

    it "strips surrounding whitespace" do
      expect(described_class.text("  Bonjour  ")).to eq("Bonjour")
    end

    it "returns the value unchanged when already clean" do
      expect(described_class.text("Bonjour")).to eq("Bonjour")
    end

    it "does not strip internal whitespace" do
      expect(described_class.text("  Cave Gest  ")).to eq("Cave Gest")
    end
  end

  describe ".zip" do
    it "returns nil for nil and values without digits" do
      expect(described_class.zip(nil)).to be_nil
      expect(described_class.zip("")).to be_nil
      expect(described_class.zip("   ")).to be_nil
      expect(described_class.zip("N/C")).to be_nil
    end

    it "keeps only digits" do
      expect(described_class.zip("75 001A")).to eq("75001")
    end

    it "pads French postcodes to 5 digits" do
      expect(described_class.zip(1000, "FR")).to eq("01000")
      expect(described_class.zip("01000", "FR")).to eq("01000")
    end

    it "keeps German postcodes to 5 digits" do
      expect(described_class.zip("10115", "DE")).to eq("10115")
    end

    it "keeps Belgian postcodes to 4 digits" do
      expect(described_class.zip("1110", "BE")).to eq("1110")
    end

    it "defaults to French 5-digit padding" do
      expect(described_class.zip(1000)).to eq("01000")
    end
  end

  describe ".country_code" do
    it "returns nil for nil, empty and unknown values" do
      expect(described_class.country_code(nil)).to be_nil
      expect(described_class.country_code("")).to be_nil
      expect(described_class.country_code("   ")).to be_nil
      expect(described_class.country_code("España")).to be_nil
    end

    it "normalizes French spellings to FR" do
      expect(described_class.country_code("France")).to eq("FR")
      expect(described_class.country_code("fr")).to eq("FR")
      expect(described_class.country_code("FRANCE")).to eq("FR")
      expect(described_class.country_code("FR")).to eq("FR")
    end

    it "normalizes Belgian spellings to BE" do
      expect(described_class.country_code("Belgique")).to eq("BE")
      expect(described_class.country_code("be")).to eq("BE")
      expect(described_class.country_code("BE")).to eq("BE")
    end

    it "normalizes Allemagne to DE instead of the AL prefix" do
      expect(described_class.country_code("Allemagne")).to eq("DE")
      expect(described_class.country_code("alleMAGNE")).to eq("DE")
      expect(described_class.country_code("DE")).to eq("DE")
    end
  end

  describe ".decimal" do
    it "returns nil for nil, blank and N/C" do
      expect(described_class.decimal(nil)).to be_nil
      expect(described_class.decimal("")).to be_nil
      expect(described_class.decimal("   ")).to be_nil
      expect(described_class.decimal("N/C")).to be_nil
      expect(described_class.decimal("n/c")).to be_nil
    end

    it "parses a French comma decimal" do
      expect(described_class.decimal("13,32")).to eq(13.32)
      expect(described_class.decimal("5,50")).to eq(5.5)
    end

    it "accepts a currency or percentage suffix" do
      expect(described_class.decimal("  19,31 EUR ")).to eq(19.31)
      expect(described_class.decimal("20%")).to eq(20.0)
    end

    it "ignores surrounding and thin spaces" do
      expect(described_class.decimal(" 12 345,67 ")).to eq(12_345.67)
    end

    it "returns nil for a value with no digits" do
      expect(described_class.decimal("abc")).to be_nil
    end
  end

  describe ".vat_number" do
    it "returns nil for nil, empty and blank strings" do
      expect(described_class.vat_number(nil)).to be_nil
      expect(described_class.vat_number("")).to be_nil
      expect(described_class.vat_number("   ")).to be_nil
    end

    it "removes spaces (including non-breaking ones) and uppercases" do
      expect(described_class.vat_number("FR 43 313181739")).to eq("FR43313181739")
      expect(described_class.vat_number("fr\u00a043\u00a0313181739")).to eq("FR43313181739")
    end

    it "keeps a compact number unchanged" do
      expect(described_class.vat_number("FR43313181739")).to eq("FR43313181739")
    end
  end
end