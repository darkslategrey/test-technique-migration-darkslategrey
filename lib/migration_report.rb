class MigrationReport
  Issue = Struct.new(:level, :source, :locator, :message, :details, keyword_init: true)

  attr_reader :issues, :counters

  def initialize
    @issues   = []
    @counters = Hash.new(0)
  end

  def count(key, by = 1)
    @counters[key.to_sym] += by
  end

  def warn(source:, locator:, message:, **details)
    add(:warning, source, locator, message, details)
  end

  def error(source:, locator:, message:, **details)
    add(:error, source, locator, message, details)
  end

  def errors   = issues.select { |issue| issue.level == :error }
  def warnings = issues.select { |issue| issue.level == :warning }

  # Libellés lisibles (non-dev) pour les compteurs techniques.
  COUNT_LABELS = {
    products_imported:  "Produits importés",
    product_conflict:   "Références en conflit rejetées",
    products_rejected:  "Produits rejetés",
    lines_ignored:      "Lignes non tarifaires ignorées",
    customers_imported: "Clients importés",
    customers_skipped:  "Clients rejetés"
  }.freeze

  def to_s
    lines = []
    lines << "===== Rapport de reprise ====="

    if @counters.empty?
      lines << "Aucun élément enregistré." unless issues.empty?
    else
      @counters.each do |key, value|
        lines << "- #{format_key(key)} : #{value}"
      end
    end

    unless issues.empty?
      lines << ""
      lines << "--- Rejetés / à corriger (#{errors.size} erreur(s)) ---"
      errors.each { |issue| lines << format_issue(issue) }
    end

    unless warnings.empty?
      lines << ""
      lines << "--- À vérifier (#{warnings.size} avertissement(s)) ---"
      warnings.each { |issue| lines << format_issue(issue) }
    end

    lines.join("\n") + "\n"
  end

  private

  def add(level, source, locator, message, details)
    @issues << Issue.new(level: level, source: source, locator: locator,
                         message: message, details: details)
  end

  def format_key(key)
    COUNT_LABELS.fetch(key, key.to_s.tr("_", " ").capitalize)
  end

  def format_issue(issue)
    line = "[#{issue.source}] #{issue.locator}: #{issue.message}"
    return line if issue.details.empty?

    body = issue.details.map do |(key, value)|
      "    #{key}: #{format_detail(value)}"
    end
    ([line] + body).join("\n")
  end

  def format_detail(value)
    case value
    when Hash
      value.map { |k, v| "#{k}=#{v}" }.join(", ")
    else
      value
    end
  end
end
