# Self-contained, descriptive reports. Patient observations never leave this process.
# The public entry point accepts the summary tables returned by summarize_observations().

sbm_report_escape <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  for (pair in list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;"),
                    c('"', "&quot;"), c("'", "&#39;"))) {
    x <- gsub(pair[1L], pair[2L], x, fixed = TRUE)
  }
  x
}

sbm_report_csv_safe <- function(df) {
  # Escape spreadsheet formulas only in text; analytical numeric columns stay numeric.
  for (nm in names(df)) {
    if (is.factor(df[[nm]])) df[[nm]] <- as.character(df[[nm]])
    if (is.character(df[[nm]])) {
      dangerous <- !is.na(df[[nm]]) & grepl("^[[:space:]]*[=+@-]|^[\t\r\n]", df[[nm]])
      df[[nm]][dangerous] <- paste0("'", df[[nm]][dangerous])
    }
  }
  df
}

sbm_report_value <- function(row, name, default = NA_real_) {
  if (!is.data.frame(row) || !nrow(row) || !name %in% names(row)) return(default)
  row[[name]][1L]
}

sbm_report_number <- function(x, suffix = "", digits = 1L) {
  if (!length(x) || is.na(x[1L]) || !is.finite(suppressWarnings(as.numeric(x[1L])))) return("Unavailable")
  paste0(formatC(as.numeric(x[1L]), format = "f", digits = digits, big.mark = ","), suffix)
}

sbm_report_count <- function(x) sbm_report_number(x, digits = 0L)

sbm_report_clock <- function(minutes) {
  if (is.null(minutes) || !length(minutes) || is.na(minutes)) return("00:00")
  sprintf("%02d:%02d", as.integer(minutes) %/% 60L, as.integer(minutes) %% 60L)
}

sbm_report_subset <- function(df, keys) {
  if (!is.data.frame(df) || !nrow(df)) return(df)
  keep <- rep(TRUE, nrow(df))
  for (nm in names(keys)) {
    if (!nm %in% names(df)) return(df[FALSE, , drop = FALSE])
    val <- keys[[nm]][1L]
    keep <- keep & if (is.na(val)) is.na(df[[nm]]) else (!is.na(df[[nm]]) & df[[nm]] == val)
  }
  df[keep, , drop = FALSE]
}

sbm_report_total <- function(df) {
  if (is.data.frame(df) && "band" %in% names(df)) {
    df <- df[!is.na(df$band) & df$band == "Total", , drop = FALSE]
  }
  df
}

sbm_report_percent <- function(numerator, denominator) {
  ifelse(!is.na(denominator) & denominator > 0, 100 * numerator / denominator, NA_real_)
}

sbm_report_pool <- function(df, dimension) {
  fields <- c("n_observations", "n_sleep_known", "n_asleep", "n_awake",
              "n_behaviour_known_awake", "n_behaviour_yes_awake")
  if (!is.data.frame(df) || !nrow(df)) return(data.frame())
  keys <- unique(df[dimension])
  keys <- keys[order(keys[[dimension]]), , drop = FALSE]
  for (field in fields) keys[[field]] <- NA_real_
  for (i in seq_len(nrow(keys))) {
    rows <- sbm_report_subset(df, keys[i, dimension, drop = FALSE])
    for (field in fields) {
      values <- rows[[field]]
      keys[[field]][i] <- if (is.null(values) || all(is.na(values))) NA_real_ else sum(values, na.rm = TRUE)
    }
  }
  keys$sleep_pct <- sbm_report_percent(keys$n_asleep, keys$n_sleep_known)
  keys$behaviour_pct <- sbm_report_percent(keys$n_behaviour_yes_awake, keys$n_behaviour_known_awake)
  keys$sleep_known_pct <- sbm_report_percent(keys$n_sleep_known, keys$n_observations)
  keys$behaviour_known_awake_pct <- sbm_report_percent(keys$n_behaviour_known_awake, keys$n_awake)
  keys
}

sbm_report_chart_data <- function(df, dimension, config) {
  pooled <- sbm_report_pool(sbm_report_total(df), dimension)
  if (dimension == "hour") {
    skeleton <- data.frame(hour = 0:23)
  } else {
    start <- as.Date(config$start_date)
    end <- as.Date(config$end_date)
    skeleton <- data.frame(report_date = seq(start, end, by = "day"))
    if (nrow(pooled)) pooled$report_date <- as.Date(pooled$report_date)
  }
  if (!nrow(pooled)) {
    for (nm in c("sleep_pct", "behaviour_pct", "n_asleep", "n_sleep_known",
                 "n_behaviour_yes_awake", "n_behaviour_known_awake")) skeleton[[nm]] <- NA_real_
    return(skeleton)
  }
  merge(skeleton, pooled, by = dimension, all.x = TRUE, sort = TRUE)
}

sbm_report_chart_svg <- function(df, dimension, title) {
  esc <- sbm_report_escape
  if (!nrow(df)) return('<p class="empty">No observations in this selection.</p>')
  n <- nrow(df)
  x <- if (n == 1L) 370 else seq(62, 692, length.out = n)
  y <- function(v) 224 - 1.7 * v
  colours <- c(sleep_pct = "#087f83", behaviour_pct = "#a65b34")
  labels <- c(sleep_pct = "Checks marked asleep", behaviour_pct = "Awake checks marked behaviour yes")
  xml <- c('<svg class="chart" viewBox="0 0 720 275" role="img" xmlns="http://www.w3.org/2000/svg">',
           paste0("<title>", esc(title), "</title>"),
           '<desc>Percentage from 0 to 100. Teal indicates recorded checks marked asleep; brown indicates observed awake checks with known behaviour status marked yes. Gaps indicate unavailable data. Exact values appear in point titles and the chart data table.</desc>')
  for (tick in c(0, 25, 50, 75, 100)) {
    xml <- c(xml, sprintf('<line x1="62" y1="%.1f" x2="692" y2="%.1f" stroke="#dce4e5"/>', y(tick), y(tick)),
             sprintf('<text x="51" y="%.1f" text-anchor="end" class="axis">%s%%</text>', y(tick) + 4, tick))
  }
  for (series in names(colours)) {
    values <- df[[series]]
    available <- is.finite(values)
    idx <- which(available)
    if (length(idx)) {
      runs <- split(idx, cumsum(c(TRUE, diff(idx) != 1L)))
      for (run in runs) {
        if (length(run) > 1L) {
          points <- paste(sprintf("%.2f,%.2f", x[run], y(values[run])), collapse = " ")
          xml <- c(xml, paste0('<polyline fill="none" stroke="', colours[[series]],
                              '" stroke-width="2.5" points="', points, '"/>'))
        }
      }
      for (j in idx) {
        period <- if (dimension == "hour") sprintf("%02d:00", df$hour[j]) else as.character(df$report_date[j])
        numerator <- if (series == "sleep_pct") df$n_asleep[j] else df$n_behaviour_yes_awake[j]
        denominator <- if (series == "sleep_pct") df$n_sleep_known[j] else df$n_behaviour_known_awake[j]
        tip <- paste0(period, ": ", labels[[series]], " ", sbm_report_number(values[j], "%"),
                      " (", sbm_report_count(numerator), "/", sbm_report_count(denominator), ")")
        xml <- c(xml, sprintf('<circle cx="%.2f" cy="%.2f" r="3.3" fill="%s"><title>%s</title></circle>',
                             x[j], y(values[j]), colours[[series]], esc(tip)))
      }
    }
  }
  ticks <- unique(round(seq(1, n, length.out = min(n, 6L))))
  for (j in ticks) {
    label <- if (dimension == "hour") sprintf("%02d:00", df$hour[j]) else format(as.Date(df$report_date[j]), "%d %b")
    xml <- c(xml, sprintf('<text x="%.2f" y="249" text-anchor="middle" class="axis">%s</text>', x[j], esc(label)))
  }
  if (!any(is.finite(df$sleep_pct)) && !any(is.finite(df$behaviour_pct))) {
    xml <- c(xml, '<text x="377" y="138" text-anchor="middle" class="axis">No known observations to plot</text>')
  }
  paste(c(xml, "</svg>"), collapse = "\n")
}

sbm_report_table <- function(df, columns, labels = columns, numeric_digits = 1L, caption = NULL) {
  esc <- sbm_report_escape
  columns <- columns[columns %in% names(df)]
  if (!length(columns) || !nrow(df)) return('<p class="empty">No summary available for this selection.</p>')
  rows <- vapply(seq_len(nrow(df)), function(i) {
    cells <- vapply(columns, function(nm) {
      val <- df[[nm]][i]
      if (is.na(val)) val <- "Unavailable"
      else if (is.numeric(val) && !inherits(val, "Date")) {
        val <- sbm_report_number(val, digits = if (startsWith(nm, "n_")) 0L else numeric_digits)
      }
      paste0("<td>", esc(val), "</td>")
    }, character(1L))
    paste0("<tr>", paste(cells, collapse = ""), "</tr>")
  }, character(1L))
  # Labels may be an ordinary parallel vector or a named map.
  label_map <- if (is.null(names(labels))) stats::setNames(labels, columns) else labels
  headings <- vapply(columns, function(nm) {
    label <- if (nm %in% names(label_map)) label_map[[nm]] else nm
    paste0('<th scope="col">', esc(label), "</th>")
  }, character(1L))
  paste0('<div class="table-scroll"><table>',
         if (!is.null(caption)) paste0("<caption>", esc(caption), "</caption>") else "",
         "<thead><tr>", paste(headings, collapse = ""), "</tr></thead><tbody>",
         paste(rows, collapse = ""), "</tbody></table></div>")
}

sbm_report_chart <- function(df, dimension, title) {
  labels <- c(report_date = "Reporting day", hour = "Local hour", sleep_pct = "Asleep (%)",
              n_asleep = "Asleep checks", n_sleep_known = "Known sleep checks",
              behaviour_pct = "Behaviour (%)", n_behaviour_yes_awake = "Awake behaviour yes",
              n_behaviour_known_awake = "Awake known behaviour")
  cols <- c(dimension, "sleep_pct", "n_asleep", "n_sleep_known", "behaviour_pct",
            "n_behaviour_yes_awake", "n_behaviour_known_awake")
  paste0('<figure><figcaption>', sbm_report_escape(title), "</figcaption>",
         sbm_report_chart_svg(df, dimension, title),
         '<div class="legend"><span><i class="teal"></i>Asleep checks (%)</span>',
         '<span><i class="brown"></i>Behaviour during awake checks (%)</span></div>',
         '<details class="chart-values"><summary>Exact chart values and denominators</summary>',
         sbm_report_table(df, cols, labels), "</details></figure>")
}

sbm_report_cards <- function(row, estimate_hours = FALSE) {
  get <- function(nm) sbm_report_value(row, nm)
  cards <- list(
    c("Recorded checks", sbm_report_count(get("n_observations")), "Point-in-time observations"),
    c("Marked asleep", sbm_report_number(get("sleep_pct"), "%"),
      paste0(sbm_report_count(get("n_asleep")), " / ", sbm_report_count(get("n_sleep_known")), " known sleep checks")),
    c("Behaviour while awake", sbm_report_number(get("behaviour_pct"), "%"),
      paste0(sbm_report_count(get("n_behaviour_yes_awake")), " / ", sbm_report_count(get("n_behaviour_known_awake")), " awake checks with known behaviour")))
  if (isTRUE(estimate_hours)) {
    cards[[length(cards) + 1L]] <- c("Standardized sleep-hours estimate",
      sbm_report_number(get("standardized_sleep_hours"), " h"), "Recorded sleep fraction scaled to 24 hours; not measured sleep duration")
  }
  paste0('<div class="metrics">', paste(vapply(cards, function(card) {
    paste0('<div class="metric"><div class="metric-label">', sbm_report_escape(card[1L]),
           '</div><div class="metric-value">', sbm_report_escape(card[2L]),
           '</div><div class="metric-note">', sbm_report_escape(card[3L]), "</div></div>")
  }, character(1L)), collapse = ""), "</div>")
}

sbm_report_completeness <- function(row) {
  get <- function(nm) sbm_report_value(row, nm)
  paste0('<p class="completeness"><strong>Recorded-field completeness:</strong> sleep status known for ',
         sbm_report_escape(sbm_report_number(get("sleep_known_pct"), "%")), " of recorded checks (",
         sbm_report_escape(sbm_report_count(get("n_sleep_known"))), "/",
         sbm_report_escape(sbm_report_count(get("n_observations"))), "); behaviour known for ",
         sbm_report_escape(sbm_report_number(get("behaviour_known_awake_pct"), "%")),
         " of explicitly awake checks (", sbm_report_escape(sbm_report_count(get("n_behaviour_known_awake"))),
         "/", sbm_report_escape(sbm_report_count(get("n_awake"))), ").</p>")
}

sbm_report_baseline <- function(df) {
  row <- sbm_report_total(df)
  if (!nrow(row)) return('<p class="muted">No matching baseline summary is available.</p>')
  sentences <- vapply(c("sleep", "behaviour"), function(metric) {
    eligible <- isTRUE(sbm_report_value(row, paste0(metric, "_eligible"), FALSE))
    label <- if (metric == "sleep") "Sleep" else "Behaviour while awake"
    if (eligible) {
      change <- sbm_report_value(row, paste0(metric, "_change_pp"))
      value <- sbm_report_number(change)
      if (!is.na(change) && change > 0) value <- paste0("+", value)
      sentence <- paste0(label, ": ", value, " percentage points; baseline ",
                         sbm_report_number(sbm_report_value(row, paste0("baseline_", metric, "_pct")), "%"),
                         ", report ", sbm_report_number(sbm_report_value(row, paste0("report_", metric, "_pct")), "%"), ".")
    } else {
      status <- sbm_report_value(row, paste0(metric, "_status"), "insufficient comparable data")
      sentence <- paste0(label, ": not compared (", status, ").")
    }
    paste0("<li>", sbm_report_escape(sentence), "</li>")
  }, character(1L))
  paste0('<div class="baseline"><h4>Change from chosen baseline</h4><ul>',
         paste(sentences, collapse = ""), "</ul></div>")
}

sbm_report_definitions <- function(config) {
  data.frame(
    term = c("Report period", "Reporting day", "Baseline", "Recorded checks", "Sleep percentage",
             "Behaviour percentage", "Recorded-field completeness", "Expected coverage", "Daily charts",
             "Hourly charts", "Unit pooling", "Equal-admission summary", "Baseline changes",
             "Unknown or unavailable", "Use", "Standardized sleep-hours estimate"),
    definition = c(
      "The selected start and end reporting dates are inclusive. Charts use only this report period.",
      paste0("Local time zone: ", config$timezone, ". Reporting day starts at ",
             sbm_report_clock(config$reporting_day_start), "; early observations may belong to the preceding reporting date."),
      paste0("A separately chosen comparison period matched to the same patient, episode, unit and time band. Each period requires at least ",
             if (is.null(config$min_baseline_observations)) 10L else config$min_baseline_observations,
             " known eligible checks and ", if (is.null(config$min_completeness_pct)) 80 else config$min_completeness_pct,
             "% recorded-field completeness for the measure being compared."),
      "Point-in-time observations, not continuous measurements and not independently sampled clinical trials.",
      "100 x recorded checks marked asleep / recorded checks with a known sleep status.",
      "100 x explicitly awake checks marked behaviour yes / explicitly awake checks with a known behaviour status. Checks asleep or with unknown sleep status are excluded.",
      "Sleep: known sleep checks / all recorded checks. Behaviour: known behaviour among explicitly awake checks / all explicitly awake checks. These describe fields in existing records.",
      "Unavailable without an observation schedule or equivalent expected-record specification. An unknown value in an existing record is different from an absent scheduled record.",
      "Report-period observations pooled within each reporting date. Missing dates or zero eligible denominators appear as gaps, never zero percentages.",
      "Report-period observations pooled by local clock hour. Both instances of a repeated daylight-saving clock hour enter that hour once per record; the chart does not measure elapsed-hour exposure.",
      "Pooled unit percentages use sums of eligible recorded checks, giving more weight to patient stays with more observations. Unit charts use this method.",
      "Arithmetic mean of eligible patient-episode percentages within the unit. Each stay with an available percentage has equal weight; denominators are numbers of eligible stays, not checks.",
      "Report percentage minus baseline percentage, in percentage points, only when both periods satisfy the configured eligibility rules. Changes are descriptive; observation patterns and clinical context can affect them.",
      "Unavailable means no eligible denominator or comparison. Unknown recorded values are not recoded as no behaviour or awake.",
      "Descriptive observational support for clinical discussion, family review and operational planning. The report does not determine diagnosis, causes, medication effects or staffing requirements.",
      if (isTRUE(config$estimate_hours)) "Enabled: recorded sleep fraction scaled to a standard 24-hour day for Total rows (or band length for band rows). This is an estimate, not measured sleep duration; sparse or selective checks can bias it." else "Disabled. This report makes no claim about measured hours of sleep."
    ), stringsAsFactors = FALSE)
}

sbm_report_png <- function(df, dimension, title, path) {
  grDevices::png(path, width = 1200L, height = 550L, res = 145L, bg = "#fffefa")
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mar = c(4.2, 4.7, 4.9, 1), family = "sans", col.axis = "#475569", col.lab = "#334155")
  x <- seq_len(nrow(df))
  graphics::plot(x, rep(NA_real_, length(x)), type = "n", ylim = c(0, 100),
                 xlim = c(0.8, max(1.2, length(x) + 0.2)), xaxt = "n", yaxt = "n",
                 xlab = if (dimension == "hour") "Local clock hour" else "Reporting day",
                 ylab = "Percentage of eligible recorded checks", main = "")
  graphics::title(main = title, line = 2.2, cex.main = 0.92)
  graphics::abline(h = seq(0, 100, 25), col = "#e2e8e9")
  graphics::axis(2, at = seq(0, 100, 25), labels = paste0(seq(0, 100, 25), "%"), las = 1)
  ticks <- unique(round(seq(1, length(x), length.out = min(length(x), 7L))))
  labels <- if (dimension == "hour") sprintf("%02d:00", df$hour[ticks]) else format(as.Date(df$report_date[ticks]), "%d %b")
  graphics::axis(1, at = ticks, labels = labels)
  graphics::lines(x, df$sleep_pct, type = "o", pch = 16, cex = 0.6, lwd = 2, col = "#087f83")
  graphics::lines(x, df$behaviour_pct, type = "o", pch = 16, cex = 0.6, lwd = 2, col = "#a65b34")
  graphics::legend("top", c("Asleep checks", "Behaviour during awake checks"),
                   col = c("#087f83", "#a65b34"), lty = 1, pch = 16, bty = "n", cex = 0.73,
                   horiz = TRUE, inset = c(0, -0.16), xpd = NA)
  invisible(path)
}

write_monitoring_report <- function(results, config, output_dir) {
  required <- c("patient", "unit", "daily", "hourly", "baseline", "quality")
  if (!is.list(results) || !all(required %in% names(results))) stop("Report requires the complete monitoring summary result.")
  if (!all(vapply(results[required], is.data.frame, logical(1L)))) stop("All report summaries must be data frames.")
  if (is.null(config$title) || !nzchar(config$title)) config$title <- "Sleep & Behaviour Monitoring"
  if (is.null(config$version)) config$version <- "Unspecified"
  if (is.null(config$baseline_start)) config$baseline_start <- as.Date(NA)
  if (is.null(config$baseline_end)) config$baseline_end <- as.Date(NA)
  start <- as.Date(config$start_date)
  end <- as.Date(config$end_date)
  if (length(start) != 1L || length(end) != 1L || is.na(start) || is.na(end) || end < start) stop("A valid inclusive report date range is required.")
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) stop("Cannot create the report output directory.")
  esc <- sbm_report_escape
  tables <- results[required]
  for (name in c("behaviour", "behaviour_daily", "statistics", "peer_comparisons")) {
    if (is.data.frame(results[[name]])) tables[[name]] <- results[[name]]
  }
  tables$issues <- if (is.data.frame(results$issues) && all(c("row", "code", "message") %in% names(results$issues))) {
    results$issues[c("row", "code", "message")]
  } else data.frame(row = integer(), code = character(), message = character(), stringsAsFactors = FALSE)
  tables$definitions <- sbm_report_definitions(config)
  tables$definitions <- rbind(tables$definitions, data.frame(
    term = c("Individual behaviour types", "Own-history daily comparison", "Ward peer comparison", "Statistical testing", "Raw data workbook"),
    definition = c(
      "Separate explicit yes/no fields use confirmed-awake denominators. Types may co-occur; their percentages should not be added. Missing flags remain unknown. The aggregate behaviour field is not inferred from individual flags.",
      "Daily percentages have equal weight, unlike period percentages weighted by known checks. Report minus baseline daily mean is descriptive; observed days and quality are shown. The same person, admission and unit are matched.",
      "Same-unit current-period eligible admission percentages, excluding every admission of the index person. Patient selection does not narrow the peer reference. Minimum distinct-peer and recorded-quality rules apply. Comparisons are descriptive and not adjusted for patient needs or case mix.",
      "Experimental inference is disabled by default after null simulations exposed excess false-positive rates. No statistical significance claim is available by default. An opt-in Newey-West/Holm calculation requires local suitability review; its normal-reference p-values and intervals can be miscalibrated. See docs/STATISTICS.md in the source repository.",
      "The Raw data worksheet contains selected source rows from the report and baseline periods, plus separate derived fields. Ward references can include additional people whose raw rows are outside that selection. Raw rows are not embedded in HTML or summary CSVs. Excel filters change the visible rows, not the calculated charts: regenerate the report after edits."
    ), stringsAsFactors = FALSE))
  csv_paths <- stats::setNames(character(length(tables)), names(tables))
  for (nm in names(tables)) {
    csv_paths[[nm]] <- file.path(output_dir, paste0("summary-", nm, ".csv"))
    utils::write.csv(sbm_report_csv_safe(tables[[nm]]), csv_paths[[nm]], row.names = FALSE, na = "", fileEncoding = "UTF-8")
  }
  charts <- list()
  add_chart <- function(scope, df, dimension, title) {
    data <- sbm_report_chart_data(df, dimension, config)
    charts[[length(charts) + 1L]] <<- list(scope = scope, data = data, dimension = dimension, title = title)
    sbm_report_chart(data, dimension, title)
  }
  total_patients <- sbm_report_total(results$patient)
  identity <- c("patient_id", "episode_id", "unit")
  patient_keys <- unique(total_patients[identity])
  count_patients <- if (nrow(patient_keys)) length(unique(patient_keys$patient_id)) else 0L
  count_episodes <- if (nrow(patient_keys)) nrow(unique(patient_keys[c("patient_id", "episode_id")])) else 0L
  unit_keys <- unique(results$unit["unit"])
  pooled <- if (nrow(total_patients)) sbm_report_pool(transform(total_patients, report_group = "report"), "report_group") else data.frame()
  baseline_label <- if (is.na(config$baseline_start) || is.na(config$baseline_end)) "No baseline selected" else
    paste0(format(as.Date(config$baseline_start), "%d %b %Y"), " – ", format(as.Date(config$baseline_end), "%d %b %Y"))
  period_label <- paste0(format(start, "%d %b %Y"), " – ", format(end, "%d %b %Y"))
  band_columns <- c("band", "n_observations", "sleep_pct", "n_sleep_known", "behaviour_pct", "n_behaviour_known_awake")
  band_labels <- c("Time band", "Recorded checks", "Asleep (%)", "Known sleep checks", "Behaviour (%)", "Awake known behaviour")
  sections <- c('<main id="main"><header class="report-header"><div class="eyebrow">SLEEP &amp; BEHAVIOUR MONITORING</div>',
                paste0('<h1>', esc(config$title), '</h1><div class="report-meta"><span>', esc(period_label),
                       '</span><span>', esc(config$timezone), ' · day starts ', esc(sbm_report_clock(config$reporting_day_start)), '</span>',
                       if (isTRUE(config$synthetic)) '<span class="badge">Synthetic demonstration</span>' else '<span class="badge">Local observation report</span>',
                       '</div><p class="intro">Recorded sleep and behaviour patterns for team discussion, family review and operational planning.</p></header>'),
                '<nav class="report-nav" aria-label="Report sections"><a href="#overview">Overview</a><a href="#units">Unit views</a><a href="#patients">Patient views</a><a href="#definitions">Definitions &amp; data quality</a></nav>',
                '<section id="overview"><div class="section-heading"><div><p class="eyebrow">REPORT OVERVIEW</p><h2>Patterns in the recorded checks</h2></div></div>',
                paste0('<p class="muted">', esc(count_patients), ' patients · ', esc(count_episodes), ' patient stays · ',
                       esc(nrow(unit_keys)), ' units. Baseline: ', esc(baseline_label), '.</p>'),
                sbm_report_cards(pooled), sbm_report_completeness(pooled),
                '<p class="note">Percentages describe recorded checks. An unknown field differs from a missing scheduled record; expected observation coverage is unavailable without a schedule. These patterns do not determine diagnosis, causes or medication effects.</p></section>',
                '<section id="units"><p class="eyebrow">UNIT VIEWS</p><h2>Shared patterns, with denominators</h2><p class="muted">Unit cards and charts pool eligible recorded checks. Stays with more checks contribute more weight.</p>')
  for (i in seq_len(nrow(unit_keys))) {
    key <- unit_keys[i, , drop = FALSE]
    all_rows <- sbm_report_subset(results$unit, key)
    unit_rows <- sbm_report_subset(sbm_report_total(all_rows), data.frame(aggregation = "pooled_observations"))
    equal <- sbm_report_subset(sbm_report_total(all_rows), data.frame(aggregation = "equal_admission"))
    title <- paste0("Unit ", key$unit)
    sections <- c(sections, paste0('<article class="panel"><h3>', esc(title), '</h3>'),
      sbm_report_cards(unit_rows, config$estimate_hours), sbm_report_completeness(unit_rows),
      '<div class="chart-grid">',
      add_chart("unit", sbm_report_subset(results$daily, key), "report_date", paste0(title, " · daily pattern")),
      add_chart("unit", sbm_report_subset(results$hourly, key), "hour", paste0(title, " · time-of-day pattern")), '</div>')
    if (nrow(equal)) sections <- c(sections,
      paste0('<p class="muted"><strong>Equal weight per eligible stay:</strong> sleep ',
             esc(sbm_report_number(sbm_report_value(equal, "sleep_pct"), "%")), ' across ',
             esc(sbm_report_count(sbm_report_value(equal, "n_sleep_admissions"))), ' stays; behaviour ',
             esc(sbm_report_number(sbm_report_value(equal, "behaviour_pct"), "%")), ' across ',
             esc(sbm_report_count(sbm_report_value(equal, "n_behaviour_admissions"))), ' stays. These averages use stays as the denominator.</p>'))
    sections <- c(sections, '<details class="chart-values"><summary>Unit time-band summary</summary>',
      sbm_report_table(sbm_report_subset(all_rows, data.frame(aggregation = "pooled_observations")), band_columns, band_labels),
      '</details></article>')
  }
  if (!nrow(unit_keys)) sections <- c(sections, '<p class="empty">No unit summaries in the report period.</p>')
  sections <- c(sections, '</section><section id="patients"><p class="eyebrow">PATIENT VIEWS</p><h2>Review one patient stay at a time</h2><p class="muted">Open a stay for daily and time-of-day charts, time-band summaries, and an eligible baseline comparison.</p>')
  for (i in seq_len(nrow(patient_keys))) {
    key <- patient_keys[i, , drop = FALSE]
    rows <- sbm_report_subset(results$patient, key)
    total <- sbm_report_total(rows)
    title <- paste0("Patient ", key$patient_id, " · Stay ", key$episode_id, " · Unit ", key$unit)
    sections <- c(sections, paste0('<details class="patient-panel"><summary><span>', esc(title),
                                  '</span><span class="muted">', esc(sbm_report_count(sbm_report_value(total, "n_observations"))),
                                  ' checks</span></summary><div class="patient-content">'),
      sbm_report_cards(total, config$estimate_hours), sbm_report_completeness(total),
      sbm_report_baseline(sbm_report_subset(results$baseline, key)), '<div class="chart-grid">',
      add_chart("patient", sbm_report_subset(results$daily, key), "report_date", paste0(title, " · daily pattern")),
      add_chart("patient", sbm_report_subset(results$hourly, key), "hour", paste0(title, " · time-of-day pattern")),
      '</div><h4>Time-band summary</h4>', sbm_report_table(rows, band_columns, band_labels))
    if (is.data.frame(results$statistics)) sections <- c(sections,
      '<h4>Data science: own-history daily comparison</h4><p class="note">Each day has equal weight. Experimental inference is disabled by default because its false-positive calibration is unresolved. An unavailable interval or p-value is not evidence of no change. See the status for each measure.</p>',
      sbm_report_table(sbm_report_subset(results$statistics, key),
        c("metric", "baseline_mean_pct", "report_mean_pct", "effect_pp", "n_baseline_days", "n_report_days", "ci_low_pp", "ci_high_pp", "p_adjusted", "status"),
        c("Measure", "Baseline daily mean (%)", "Report daily mean (%)", "Change (pp)", "Baseline days", "Report days", "Experimental interval lower (pp)", "Experimental interval upper (pp)", "Experimental Holm p", "Test status"), numeric_digits = 3L))
    if (is.data.frame(results$behaviour)) sections <- c(sections,
      '<h4>Each recorded behaviour</h4>',
      sbm_report_table(sbm_report_total(sbm_report_subset(results$behaviour, key)),
        c("metric", "n_yes", "n_known", "n_eligible", "rate_pct", "completeness_pct"),
        c("Behaviour", "Yes checks", "Known checks", "Awake checks", "Rate (%)", "Field complete (%)")))
    if (is.data.frame(results$peer_comparisons)) sections <- c(sections,
      '<h4>Ward peers: descriptive comparison</h4><p class="muted">The reference excludes this person across all admissions and gives each eligible peer admission equal weight. Patient needs and recording practices can affect differences.</p>',
      sbm_report_table(sbm_report_subset(results$peer_comparisons, key),
        c("metric", "report_rate_pct", "peer_mean_pct", "difference_pp", "peer_median_pct", "percentile_midrank", "n_peer_patients", "n_peer_admissions", "status"),
        c("Measure", "Person (%)", "Peer mean (%)", "Difference (pp)", "Peer median (%)", "Peer percentile", "Peer people", "Peer stays", "Status")))
    sections <- c(sections, '</div></details>')
  }
  if (!nrow(patient_keys)) sections <- c(sections, '<p class="empty">No patient summaries in the report period.</p>')
  quality_view <- results$quality
  quality_labels <- c(report_observations = "Recorded checks in report period",
    baseline_observations = "Recorded checks in baseline period",
    patient_episode_unit_groups = "Patient stay and unit groups",
    unknown_sleep_observations = "Recorded checks with unknown sleep status",
    unknown_behaviour_among_awake_observations = "Awake checks with unknown behaviour status",
    behaviour_yes_excluded_from_awake_denominator = "Behaviour yes checks excluded because sleep status was asleep or unknown",
    recorded_sleep_state_completeness_pct = "Recorded sleep-field completeness (%)",
    recorded_awake_behaviour_completeness_pct = "Recorded awake behaviour-field completeness (%)")
  if (nrow(quality_view)) {
    quality_view$value <- vapply(seq_len(nrow(quality_view)), function(i) {
      sbm_report_number(quality_view$value[i], digits = if (endsWith(quality_view$metric[i], "_pct")) 1L else 0L)
    }, character(1L))
    matched <- quality_view$metric %in% names(quality_labels)
    quality_view$metric[matched] <- unname(quality_labels[quality_view$metric[matched]])
  }
  issue_html <- if (nrow(tables$issues)) {
    issue_counts <- as.data.frame(table(tables$issues$code), stringsAsFactors = FALSE)
    names(issue_counts) <- c("code", "n_issues")
    issue_counts <- issue_counts[order(-issue_counts$n_issues, issue_counts$code), , drop = FALSE]
    paste0('<p class="muted">Validation diagnostics use original source row numbers and contain no original field values. ',
           esc(nrow(tables$issues)), ' issues are listed across ', esc(length(unique(tables$issues$row))),
           ' source rows. One row can have several issues.</p>',
           sbm_report_table(issue_counts, c("code", "n_issues"), c("Issue code", "Issues")),
           sbm_report_table(utils::head(tables$issues, 200L), c("row", "code", "message"),
                            c("Source row", "Issue code", "Explanation"), numeric_digits = 0L),
           if (nrow(tables$issues) > 200L) '<p class="muted">The first 200 issues are shown here. The Documentation worksheet and summary-issues.csv contain the complete diagnostics.</p>' else '')
  } else '<p class="muted">No row-level validation issues were supplied with these summaries.</p>'
  sections <- c(sections, '</section><section id="definitions"><p class="eyebrow">READING THIS REPORT</p><h2>Definitions &amp; data quality</h2>',
                '<details class="panel"><summary>Calculation definitions and interpretation</summary>',
                sbm_report_table(tables$definitions, c("term", "definition"), c("Term", "Definition")), '</details>',
                '<details class="panel"><summary>Data quality summary</summary>',
                sbm_report_table(quality_view, c("metric", "value"), c("Measure", "Value")), '</details>',
                '<details class="panel"><summary>Source validation issues</summary>', issue_html, '</details>',
                '<p class="muted">The summary CSV files preserve numeric results for further analysis. If Excel export is installed, the workbook contains the same summaries and automatically generated charts. The four-sheet workbook includes selected report and baseline source records on Raw data.</p></section>',
                paste0('<footer>Generated ', esc(format(Sys.time(), "%Y-%m-%d %H:%M %Z")), ' · Version ', esc(config$version),
                       '. Descriptive observational support; interpretation requires clinical context.</footer></main>'))
  css <- "
:root{color-scheme:light;--ink:#19313b;--muted:#5c6e75;--teal:#087f83;--line:#dce5e4;--paper:#fffefa;--wash:#f1f5f3}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f3f5f2;color:var(--ink);font:15px/1.55 system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}main{max-width:1320px;margin:0 auto;padding:48px 40px;background:var(--paper)}a{color:#076b70}a:focus-visible,summary:focus-visible{outline:3px solid #ae6847;outline-offset:4px}.skip{position:absolute;left:-9999px}.skip:focus{left:20px;top:12px;background:white;padding:8px}.eyebrow{font-size:11px;letter-spacing:1.7px;font-weight:750;color:var(--teal);margin:0 0 10px}.report-header h1{font-size:clamp(27px,3.7vw,42px);line-height:1.15;letter-spacing:-1px;font-weight:650;margin:0 0 18px}.report-meta{display:flex;align-items:center;flex-wrap:wrap;gap:12px 22px;font-size:13px;color:var(--muted)}.badge{padding:4px 10px;border-radius:20px;background:#e3f0eb;color:#1d625d;font-size:12px;font-weight:650}.intro{max-width:750px;font-size:17px;margin:18px 0 25px;color:var(--muted)}.report-nav{display:flex;flex-wrap:wrap;gap:8px 26px;border-top:1px solid var(--line);border-bottom:1px solid var(--line);padding:14px 0;margin:0 0 34px}.report-nav a{text-decoration:none;font-size:13px;font-weight:650}section{scroll-margin-top:20px;margin:0 0 46px}h2{font-weight:650;font-size:25px;letter-spacing:-.4px;line-height:1.25;margin:0 0 12px}h3{font-size:20px;margin:0 0 20px;font-weight:650}h4{font-size:14px;margin:12px 0 8px}.muted,.empty{color:var(--muted);font-size:13px}.metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(205px,1fr));gap:12px;margin:18px 0}.metric{padding:18px 20px;background:var(--wash);border:1px solid #e1e9e5;border-radius:10px}.metric-label{font-size:12px;font-weight:650;color:var(--muted)}.metric-value{font-size:31px;line-height:1.15;margin:7px 0;font-weight:650;letter-spacing:-.8px}.metric-note{font-size:11px;line-height:1.45;color:var(--muted)}.completeness{font-size:12px;color:var(--muted);margin:12px 0}.note{font-size:13px;line-height:1.6;border-left:3px solid #80aaa0;padding:8px 14px;background:#f2f6f2;max-width:1000px}.panel,.patient-panel{border:1px solid var(--line);padding:24px;border-radius:12px;margin:18px 0;background:#fffefa}.chart-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px;margin-top:20px}figure{margin:0;min-width:0}figcaption{font-size:13px;font-weight:650;overflow-wrap:anywhere}.chart{display:block;width:100%;height:auto;margin-top:4px}.axis{fill:#607178;font:11px system-ui,sans-serif}.legend{display:flex;flex-wrap:wrap;gap:6px 15px;font-size:10px;color:var(--muted)}.legend span{display:inline-flex;align-items:center;gap:5px}.legend i{display:inline-block;width:14px;height:3px}.teal{background:#087f83}.brown{background:#a65b34}.chart-values{margin-top:10px;font-size:11px}.chart-values summary{font-size:11px;color:#386c72}.table-scroll{max-width:100%;overflow-x:auto;margin:12px 0}table{width:100%;border-collapse:collapse;font-size:12px;text-align:left}caption{text-align:left;font-size:12px;font-weight:650;margin:8px 0}th{background:#edf3f0;color:#39535b;font-size:11px;font-weight:650}th,td{padding:10px 12px;border-bottom:1px solid var(--line);vertical-align:top}td{font-variant-numeric:tabular-nums}tbody tr:last-child td{border-bottom:0}.patient-panel{padding:0}.patient-panel>summary{padding:19px 23px;font-weight:650;font-size:14px;display:list-item;cursor:pointer}.patient-panel>summary>span:last-child{float:right;font-weight:400;margin-left:12px}.patient-content{padding:0 23px 24px}.baseline{border-left:3px solid #c4d6d2;padding:3px 15px;margin:20px 0;font-size:13px}.baseline ul{padding-left:18px;margin:8px 0}.baseline li{margin:4px 0}summary{cursor:pointer}footer{border-top:1px solid var(--line);padding-top:18px;color:var(--muted);font-size:11px}#definitions .panel>summary{font-weight:650;font-size:14px}#definitions td:first-child{width:200px;font-weight:600}
@media(max-width:850px){main{padding:28px 18px}.chart-grid{grid-template-columns:1fr}.panel{padding:18px}.metrics{grid-template-columns:repeat(auto-fit,minmax(155px,1fr))}.metric{padding:14px}.metric-value{font-size:28px}.patient-panel>summary>span:last-child{float:none;display:block;margin:6px 0 0}.patient-content{padding:0 15px 18px}}
@media print{@page{size:A4 landscape;margin:12mm}html{scroll-behavior:auto}body,main{background:white}main{max-width:none;padding:0}body{font-size:11px}.report-nav,.skip,.chart-values{display:none!important}h1{font-size:27px!important}h2{font-size:20px}.panel,.patient-panel{break-inside:avoid;page-break-inside:avoid;padding:15px}.patient-content{padding:0 8px 10px}.patient-panel>summary{padding:10px 8px}.patient-panel::details-content{display:block!important;content-visibility:visible!important}.patient-panel>*{display:block!important}.metrics{margin:10px 0;grid-template-columns:repeat(3,1fr)}.metric{padding:9px}.metric-value{font-size:25px}.metric-label,.metric-note{font-size:10px}.chart-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.chart{max-height:220px}.patient-panel{break-before:page}section{margin-bottom:25px}footer{font-size:9px}*{-webkit-print-color-adjust:exact;print-color-adjust:exact}}
"
  html <- paste0('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
                 '<meta http-equiv="Content-Security-Policy" content="default-src &#39;none&#39;; style-src &#39;unsafe-inline&#39;; img-src data:; base-uri &#39;none&#39;; form-action &#39;none&#39;">',
                 '<title>', esc(config$title), '</title><style>', css, '</style></head><body><a class="skip" href="#main">Skip to report</a>',
                 paste(sections, collapse = "\n"), '</body></html>')
  html_path <- file.path(output_dir, "report.html")
  writeLines(enc2utf8(html), html_path, useBytes = TRUE)
  workbook_path <- write_dashboard_workbook(results, config, output_dir)
  invisible(list(html = html_path, csv = csv_paths, workbook = workbook_path))
}
