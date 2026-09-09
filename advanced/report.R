# No JavaScript, external assets, patient-level predictions, or network calls.
advanced_escape <- function(x) {
  x <- as.character(x); x[is.na(x)] <- ""
  for (pair in list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;"), c('"', "&quot;"), c("'", "&#39;")))
    x <- gsub(pair[1L], pair[2L], x, fixed = TRUE)
  x
}

advanced_csv <- function(data, path) {
  for (field in names(data)) if (is.character(data[[field]])) {
    dangerous <- !is.na(data[[field]]) & grepl("^[[:space:]]*[=+@-]|^[\t\r\n]", data[[field]])
    data[[field]][dangerous] <- paste0("'", data[[field]][dangerous])
  }
  write.csv(data, path, row.names = FALSE, na = "")
}

advanced_table <- function(data) {
  if (!nrow(data)) return("<p>No eligible records for this table.</p>")
  values <- lapply(data, function(x) {
    if (is.numeric(x)) ifelse(is.na(x), "Unavailable", format(round(x, 2), trim = TRUE, scientific = FALSE))
    else { x <- as.character(x); x[is.na(x)] <- "Unavailable"; x }
  })
  rows <- vapply(seq_len(nrow(data)), function(i) paste0("<tr>", paste0("<td>",
    advanced_escape(vapply(values, `[`, character(1L), i)), "</td>", collapse = ""), "</tr>"), character(1L))
  paste0('<div class="table-scroll"><table><thead><tr>', paste0("<th>", advanced_escape(gsub("_", " ", names(data), fixed = TRUE)),
    "</th>", collapse = ""), "</tr></thead><tbody>", paste(rows, collapse = ""), "</tbody></table></div>")
}

write_advanced_report <- function(cohorts, joined, backtest, issues, config, policy, output) {
  tables <- list("demographic-cohorts" = cohorts, "demographic-join-audit" = joined$audit,
    "backtest-summary" = backtest$summary, "backtest-coverage" = backtest$coverage, "research-readiness" = backtest$readiness)
  issue_counts <- if (nrow(issues)) aggregate(list(n_observations = rep(1L, nrow(issues))), list(issue_code = issues$code), sum)
    else data.frame(issue_code = character(), n_observations = integer())
  tables[["data-quality-summary"]] <- issue_counts
  for (name in names(tables)) advanced_csv(tables[[name]], file.path(output, paste0(name, ".csv")))
  links <- paste0('<li><a href="', names(tables), '.csv">', advanced_escape(gsub("-", " ", names(tables), fixed = TRUE)), '</a></li>', collapse = "")
  html <- paste0('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; base-uri \'none\'; form-action \'none\'">',
    '<title>Sleep and behaviour | Research edition</title><style>',
    ':root{font-family:system-ui,sans-serif;color:#163047;background:#eef3f6}body{margin:0}main{max-width:1320px;margin:auto;padding:28px}',
    'header{background:#143b51;color:white;padding:30px;border-radius:16px}header p{max-width:860px;line-height:1.5}',
    '.tag{display:inline-block;background:#d9f2ed;color:#164f43;padding:6px 12px;border-radius:20px;font-size:.8rem;font-weight:700}',
    'section{background:white;border:1px solid #dbe4e9;border-radius:12px;padding:24px;margin-top:20px}h1{margin-bottom:8px}h2{margin-top:0}',
    'p,li{line-height:1.55}.note{border-left:4px solid #ad732c;padding-left:16px}.table-scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-size:.84rem}',
    'th,td{padding:10px;text-align:left;border-bottom:1px solid #dbe4e9}th{background:#edf3f6;white-space:normal}tr:nth-child(even){background:#f8fafb}',
    'a{color:#136858}.muted{color:#526877}details{margin:15px 0}summary{cursor:pointer;font-weight:650}@media print{body{background:white}main{padding:0}section{break-inside:avoid}.table-scroll{overflow:visible}}',
    '</style></head><body><main><header><span class="tag">', if (isTRUE(config$synthetic)) 'SYNTHETIC DATA · RESEARCH EDITION' else 'LOCAL DATA · RESEARCH EDITION',
    '</span><h1>Sleep and behaviour research</h1><p>Explore demographic patterns and measure how simple historical baselines perform on later recorded days.</p>',
    '<p>', advanced_escape(config$title), ' · Report dates ', config$start_date, ' to ', config$end_date, '</p></header>',
    '<section><h2>What this edition can establish</h2><p>Demographic comparisons are descriptive. Age, recorded sex and diagnostic group are used to group observations; they do not adjust for case mix, treatment, staffing or observation frequency. No causal effect or statistical significance is claimed.</p>',
    '<p class="note">Next-day clinical forecasts and medical recommendations are disabled. Backtest results are retrospective research evidence, not a validated prediction service. ',
    if (isTRUE(config$synthetic)) 'The observations and demographics are fictional. Their backtest errors do not establish performance on real patients.' else 'These outputs may contain sensitive group labels and small contributor counts. Handle them in the same approved environment as the input data.', '</p></section>',
    '<section><h2>Next-day baseline evaluation</h2><p>The predeclared holdout is ', backtest$holdout_start, ' to ', backtest$holdout_end,
    ' (14 calendar dates ending on the configured EndDate). Both methods are evaluated on exactly the same eligible patient, episode, unit and target date for each outcome. Lower mean absolute error (MAE) is better; the unit is percentage points.</p>',
    advanced_table(backtest$summary),
    '<p><strong>Last observed day:</strong> yesterday’s eligible recorded percentage. <strong>Trailing seven-day mean:</strong> an equal-day average of eligible dates in the seven calendar days immediately before the target, with at least ', policy$MinHistoryDays,
    ' available days. Both require an eligible immediately previous day. Gaps are not bridged, and future or target-day observations never enter a prediction.</p>',
    '<p>Walk-forward evaluation allows earlier holdout outcomes to become history for later dates. The methods have no fitted parameters. Each target has equal weight; errors are not weighted by the number of observations. No model selection, uncertainty interval, external validation or deployment approval is implied.</p>',
    '<details><summary>Eligibility and exclusions</summary><p>Each history day and target day needs at least ', policy$MinKnownPerDay,
    ' known observations and ', policy$MinCompletenessPct, '% recorded completeness for its outcome. Completeness uses recorded observations, not expected checks; there is no observation schedule input. Missing target dates have no outcome and are never synthesized. Counts below cover observed holdout target rows only; they are not a coverage rate for all occupied bed-days.</p>',
    advanced_table(backtest$coverage), advanced_table(backtest$readiness), '</details></section>',
    '<section><h2>Demographic patterns</h2><p>Sleep is the percentage of known sleep observations recorded asleep. Behaviour is the percentage of known behaviour observations recorded yes among confirmed-awake observations. These are observation percentages, not measured hours or event probabilities.</p>',
    '<p>Rates pool known observations within each group. Patients observed more often have greater weight. Each dimension is shown separately for all selected units and by unit. Metrics and observation denominators are suppressed below ', policy$MinGroupPatients,
    ' distinct contributing patients; contributor counts remain visible. Suppression is a reporting safeguard and does not make this output anonymous.</p>',
    advanced_table(cohorts), '</section><section><h2>Data preparation</h2><p>Demographics joins use patient and episode together. Missing records remain in an Unknown group; unused demographic rows are counted. Every selected observation is retained exactly once. Join counts cover configured report and baseline dates; demographic rates cover report dates only.</p>',
    advanced_table(joined$audit), '<details><summary>Observation quality issues</summary>', advanced_table(issue_counts), '</details></section>',
    '<section><h2>Download analysis tables</h2><ul>', links,
    '</ul><p class="muted">The report exports aggregate tables only. Patient-level paired backtest rows are kept inside the analysis process and are not written. The local receipt records inputs and research policy hashes for reproducibility.</p></section>',
    '<section><h2>What must come before a demographic prediction model</h2><p>Agree a useful clinical or operational decision and outcome; check recording schedules, missingness and changes in practice; establish sufficient representative admissions; predeclare an evaluation plan; compare with these baselines using temporal and patient-separated tests; then assess calibration, subgroup performance and prospective workflow impact. Demographic inputs are not predictive features in this edition.</p></section>',
    '</main></body></html>')
  writeLines(html, file.path(output, "research-report.html"), useBytes = TRUE)
}
