namespace :import do
  desc "Rejoue la reprise et affiche le rapport synthétique (créés / rejetés / à vérifier)"
  task :report_imports do
    report = MigrationReport.new
    data   = DATA_DIR

    ProductPrice::Import::Cavegest.new(File.join(data, "export_tarifs_cavegest.csv"), report: report).call
    Customer::Import::Cavegest.new(File.join(data, "export_clients_cavegest.xlsx"), report: report).call

    output = report.to_s

    FileUtils.mkdir_p(File.join(APP_ROOT, "tmp"))
    File.write(File.join(APP_ROOT, "tmp", "report.txt"), output)

    puts output
    puts "\n>>> Rapport sauvegardé dans tmp/report.txt"
  end
end