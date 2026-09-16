namespace :report do
  desc "Contrôles de cohérence sur la base après reprise"
  task :audit do
    output = Importer::Audit.new.to_s

    FileUtils.mkdir_p(File.join(APP_ROOT, "tmp"))
    File.write(File.join(APP_ROOT, "tmp", "audit.txt"), output)

    puts output
    puts "\n>>> Audit sauvegardé dans tmp/audit.txt"
  end
end