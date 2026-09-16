namespace :import do
  namespace :customer do
    desc "Importe les clients CaveGest"
    task :cavegest do
      report = MigrationReport.new
      Customer::Import::Cavegest.new(File.join(DATA_DIR, "export_clients_cavegest.xlsx"), report: report).call

      output = report.to_s

      FileUtils.mkdir_p(File.join(APP_ROOT, "tmp"))
      File.write(File.join(APP_ROOT, "tmp", "customers_report.txt"), output)

      puts output
      puts "\n>>> Rapport clients sauvegardé dans tmp/customers_report.txt"
    end
  end
end
