namespace :import do
  namespace :product_price do
    desc "Importe les produits et grilles tarifaires CaveGest"
    task :cavegest do
      report = MigrationReport.new
      ProductPrice::Import::Cavegest.new(File.join(DATA_DIR, "export_tarifs_cavegest.csv"), report: report).call

      output = report.to_s

      FileUtils.mkdir_p(File.join(APP_ROOT, "tmp"))
      File.write(File.join(APP_ROOT, "tmp", "products_report.txt"), output)

      puts output
      puts "\n>>> Rapport produits sauvegardé dans tmp/products_report.txt"
    end
  end
end
