#!/usr/bin/env Rscript
# Hand-calculated synthetic fixtures. Optional Excel checks use openxlsx when installed.
args <- commandArgs(trailingOnly = FALSE)
script_arg <- args[startsWith(args, "--file=")]
repo_root <- if (length(script_arg)) {
  dirname(dirname(normalizePath(sub("^--file=", "", script_arg[[1]]))))
} else normalizePath(".")
for (module in c("config.R", "analytics.R", "extended.R", "statistics.R", "raw_data.R", "report.R", "workbook.R"))
  source(file.path(repo_root, "R", module))

results <- list()
test <- function(name, expr) {
  error <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  results[[length(results) + 1L]] <<- list(name = name, error = error)
  cat(if (is.null(error)) "PASS" else "FAIL", "-", name, "\n")
  if (!is.null(error)) cat("  ", error, "\n", sep = "")
}
expect_equal <- function(actual, expected, tolerance = 1e-8) {
  if (!isTRUE(all.equal(actual, expected, tolerance = tolerance,
                       check.attributes = FALSE))) {
    stop("Expected ", paste(expected, collapse = ", "), "; received ",
         paste(actual, collapse = ", "), call. = FALSE)
  }
}
expect_true <- function(value, message = "Expected TRUE") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
expect_error <- function(expr, pattern = NULL) {
  error <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  if (is.null(error)) stop("Expected rejection, but input was accepted", call. = FALSE)
  if (!is.null(pattern) && !grepl(pattern, error, ignore.case = TRUE)) {
    stop("Unexpected error: ", error, call. = FALSE)
  }
  invisible(error)
}

test_config <- function(...) {
  config <- list(
    title = "Synthetic test report", timezone = "UTC", synthetic = TRUE,
    columns = c(observation_id = "observation_id", patient_id = "patient_id",
                episode_id = "episode_id", unit = "unit", observed_at = "observed_at",
                sleep_state = "sleep_state", behaviour = "behaviour",
                awake_calm = "awake_calm", sleeping = "sleeping"),
    codes = list(awake = "awake", asleep = "asleep", behaviour_yes = "yes",
                 behaviour_no = "no", awake_calm = "yes", sleeping = "yes"),
    bands = data.frame(name = c("Night", "Day", "Evening"),
                       start = c(0, 480, 960), end = c(480, 960, 1440)),
    reporting_day_start = 0,
    start_date = as.Date("2026-08-02"), end_date = as.Date("2026-08-02"),
    baseline_start = as.Date("2026-08-01"), baseline_end = as.Date("2026-08-01"),
    units = character(), patients = character(),
    min_completeness_pct = 80, min_baseline_observations = 1,
    estimate_hours = FALSE, behaviour_columns = character(), min_peer_patients = 3L,
    statistics_enabled = FALSE, min_stat_days = 28L, min_stat_known_per_day = 6L,
    hac_lag = 7L, alpha = 0.05
  )
  for (key in names(list(...))) config[[key]] <- list(...)[[key]]
  config
}
fixture <- function(sleep, behaviour = rep("no", length(sleep)),
                    patient = rep("SYN-001", length(sleep)),
                    unit = rep("Sample Unit", length(sleep)),
                    timestamp = NULL, episode = rep("SYN-E1", length(sleep))) {
  n <- length(sleep)
  if (is.null(timestamp)) timestamp <- sprintf("2026-08-02T01:%02d:00+0000", seq_len(n) - 1L)
  data.frame(observation_id = sprintf("SYN-O%03d", seq_len(n)), patient_id = patient,
             episode_id = episode, unit = unit, observed_at = timestamp,
             sleep_state = sleep, behaviour = behaviour,
             awake_calm = rep("", n), sleeping = rep("", n),
             stringsAsFactors = FALSE)
}
analyze <- function(data, config = test_config()) {
  normalized <- normalize_observations(data, config)
  list(normalized = normalized,
       summary = summarize_observations(normalized$data, config))
}
report_results <- function(data, config = test_config()) {
  analyzed <- analyze(data, config)
  result <- analyzed$summary
  extended <- extend_monitoring_analysis(data, analyzed$normalized, config)
  for (name in c("behaviour", "behaviour_daily", "metric_daily", "peer_comparisons"))
    result[[name]] <- extended[[name]]
  result$statistics <- compute_monitoring_statistics(extended$metric_daily, config)
  result$issues <- rbind(analyzed$normalized$issues, extended$issues)
  result$raw_data <- prepare_monitoring_raw_data(data, analyzed$normalized$data, config)
  result
}
row_for <- function(table, band = "Total", patient = NULL, unit = NULL,
                    aggregation = "pooled_observations") {
  keep <- table$band == band
  if ("aggregation" %in% names(table)) keep <- keep & table$aggregation == aggregation
  if (!is.null(patient)) keep <- keep & table$patient_id == patient
  if (!is.null(unit)) keep <- keep & table$unit == unit
  found <- table[keep, , drop = FALSE]
  expect_equal(nrow(found), 1L)
  found
}

test("Behaviour rate counts only awake observations with a known behaviour state", {
  data <- fixture(c("asleep", "awake", "awake", "awake", "", "asleep"),
                  c("yes", "yes", "no", "", "yes", "no"))
  row <- row_for(analyze(data)$summary$patient)
  expect_equal(row$n_observations, 6)
  expect_equal(row$n_sleep_known, 5)
  expect_equal(row$n_asleep, 2)
  expect_equal(row$n_awake, 3)
  expect_equal(row$sleep_pct, 40)
  expect_equal(row$sleep_known_pct, 100 * 5 / 6)
  expect_equal(row$n_behaviour_known_awake, 2)
  expect_equal(row$n_behaviour_yes_awake, 1)
  expect_equal(row$behaviour_pct, 50)
  expect_equal(row$behaviour_known_awake_pct, 100 * 2 / 3)
})

test("Every time band uses the same awake-and-known behaviour denominator", {
  data <- fixture(rep(c("asleep", "awake", "awake", "awake", "", "asleep"), 3),
                  rep(c("yes", "yes", "no", "", "yes", "no"), 3),
                  timestamp = sprintf("2026-08-02T%02d:%02d:00+0000",
                                      rep(c(1, 9, 17), each = 6), rep(0:5, 3)))
  output <- analyze(data)$summary
  for (band in c("Night", "Day", "Evening", "Total")) {
    expect_equal(row_for(output$patient, band)$behaviour_pct, 50)
    expect_equal(row_for(output$unit, band)$behaviour_pct, 50)
    expect_equal(row_for(output$daily, band)$behaviour_pct, 50)
  }
  expect_equal(output$hourly$behaviour_pct, rep(50, 3))
})

test("An entirely asleep sample has an undefined awake behaviour rate", {
  row <- row_for(analyze(fixture(c("asleep", "asleep"), c("yes", "no")))$summary$patient)
  expect_equal(row$sleep_pct, 100)
  expect_equal(row$n_behaviour_known_awake, 0)
  expect_true(is.na(row$behaviour_pct))
})

test("Blank and NA states do not become awake or behaviour-free observations", {
  row <- row_for(analyze(fixture(c("", NA_character_), c("", NA_character_)))$summary$patient)
  expect_equal(row$n_sleep_known, 0)
  expect_equal(row$n_awake, 0)
  expect_equal(row$n_behaviour_known_awake, 0)
  expect_true(is.na(row$sleep_pct))
  expect_true(is.na(row$behaviour_pct))
})

test("Patient and unit filters use exact matches", {
  data <- fixture(rep("awake", 4), patient = c("SYN-001", "SYN-0010", "SYN-001", "SYN-001"),
                  unit = c("Sample Unit", "Sample Unit", "Sample Unit Annex", "Other Unit"))
  output <- analyze(data, test_config(units = "Sample Unit", patients = "SYN-001"))
  expect_equal(nrow(output$normalized$data), 1)
  expect_equal(row_for(output$summary$patient)$n_observations, 1)
})

test("All selected patients are processed, including the fifth patient", {
  data <- fixture(rep("awake", 5), patient = sprintf("SYN-%03d", 1:5))
  output <- analyze(data)$summary$patient
  expect_equal(sort(output$patient_id[output$band == "Total"]), sprintf("SYN-%03d", 1:5))
})

test("Duplicate observation identifiers are rejected", {
  data <- fixture(c("awake", "asleep"))
  data$observation_id[2] <- data$observation_id[1]
  expect_error(analyze(data), "duplicat")
})

test("Repeated patient, episode, and instant is rejected even with a different identifier", {
  data <- fixture(c("awake", "asleep"))
  data$observed_at[2] <- data$observed_at[1]
  expect_error(analyze(data), "duplicat")
})

test("Distinct episodes remain separate at an identical timestamp", {
  data <- fixture(c("awake", "asleep"), episode = c("SYN-E1", "SYN-E2"),
                  timestamp = rep("2026-08-02T01:00:00Z", 2))
  output <- analyze(data)$summary$patient
  expect_equal(nrow(output[output$band == "Total", ]), 2)
})

test("Report filtering uses actual local dates and omits outside observations", {
  data <- fixture(rep("awake", 5), timestamp = c("2026-07-31T23:45:00-0400",
                   "2026-08-01T23:45:00-0400", "2026-08-02T23:45:00-0400",
                   "2026-08-03T00:15:00-0400", "2026-08-03T00:15:00+0900"))
  output <- analyze(data, test_config(timezone = "America/Toronto"))
  expect_equal(nrow(output$normalized$data), 3)
  expect_equal(row_for(output$summary$patient)$n_observations, 2)
  expect_equal(as.character(unique(output$summary$daily$report_date)), "2026-08-02")
})

test("Daylight-saving repeated wall-clock times remain distinct instants", {
  data <- fixture(c("awake", "asleep"), timestamp = c("2026-11-01T01:30:00-04:00",
                                                         "2026-11-01T01:30:00-05:00"))
  config <- test_config(start_date = as.Date("2026-11-01"), end_date = as.Date("2026-11-01"),
                        timezone = "America/Toronto",
                        baseline_start = as.Date("2026-10-31"), baseline_end = as.Date("2026-10-31"))
  output <- analyze(data, config)
  expect_equal(row_for(output$summary$patient)$n_observations, 2)
  expect_equal(row_for(output$summary$patient)$sleep_pct, 50)
  expect_equal(unique(output$normalized$data$hour), 1)
  expect_equal(as.character(unique(output$normalized$data$report_date)), "2026-11-01")
})

test("Two offset spellings of the same instant cannot evade duplicate detection", {
  data <- fixture(c("awake", "awake"), timestamp = c("2026-08-02T01:30:00+0000",
                                                        "2026-08-02T02:30:00+0100"))
  expect_error(analyze(data), "duplicat")
})

test("Invalid calendar dates, offset-free values, and impossible offsets are rejected", {
  for (value in c("2026-02-30T01:00:00Z", "2026-08-02T01:00:00",
                  "2026-08-02T01:00:00+2500", "2026-08-02T25:00:00Z")) {
    expect_error(analyze(fixture("awake", timestamp = value)))
  }
})

test("Bands spanning midnight include their start and exclude their end", {
  bands <- data.frame(name = c("Night", "Day"), start = c(1320, 360), end = c(360, 1320))
  data <- fixture(rep("awake", 4), timestamp = c("2026-08-02T22:00:00Z", "2026-08-02T05:59:00Z",
                                                  "2026-08-02T06:00:00Z", "2026-08-02T21:59:00Z"))
  output <- analyze(data, test_config(bands = bands))$summary$patient
  expect_equal(row_for(output, "Night")$n_observations, 2)
  expect_equal(row_for(output, "Day")$n_observations, 2)
})

test("A reporting day starting at 06:00 assigns earlier observations to the preceding day", {
  data <- fixture(c("awake", "asleep"), timestamp = c("2026-08-02T05:59:00Z", "2026-08-02T06:00:00Z"))
  output <- analyze(data, test_config(reporting_day_start = 360))
  expect_equal(as.character(output$normalized$data$report_date), c("2026-08-01", "2026-08-02"))
  expect_equal(row_for(output$summary$patient)$n_observations, 1)
  expect_equal(row_for(output$summary$patient)$sleep_pct, 100)
})

test("Pooled and equal-admission unit rates produce independently calculated results", {
  data <- fixture(c("asleep", "awake", "awake", "awake"),
                  patient = c("SYN-001", rep("SYN-002", 3)))
  output <- analyze(data)$summary$unit
  pooled <- row_for(output, aggregation = "pooled_observations")
  equal <- row_for(output, aggregation = "equal_admission")
  expect_equal(pooled$sleep_pct, 25)
  expect_equal(equal$sleep_pct, 50)
  expect_equal(pooled$n_observations, 4)
  expect_true(is.na(equal$n_observations))
  expect_equal(equal$n_admissions, 2)
})

test("Unit behaviour averages exclude admissions with no awake-known denominator", {
  data <- fixture(c(rep("awake", 4), "asleep"), c("yes", "no", "no", "no", "yes"),
                  patient = c("SYN-001", rep("SYN-002", 3), "SYN-003"))
  output <- analyze(data)$summary$unit
  pooled <- row_for(output)
  equal <- row_for(output, aggregation = "equal_admission")
  expect_equal(pooled$behaviour_pct, 25)
  expect_equal(equal$behaviour_pct, 50)
  expect_equal(equal$n_admissions, 3)
  expect_equal(equal$n_behaviour_admissions, 2)
})

test("Usable fallback sleep flags handle both blank and NA primary states", {
  data <- fixture(c("", NA_character_), c("", NA_character_))
  data$awake_calm[1] <- "yes"
  data$sleeping[2] <- "yes"
  output <- analyze(data)
  expect_equal(output$normalized$data$sleep_state, c("awake", "asleep"))
  expect_equal(output$normalized$data$behaviour, c("unknown", "unknown"))
  expect_true(is.na(row_for(output$summary$patient)$behaviour_pct))
})

test("An awake-calm fallback cannot override explicitly recorded behaviour", {
  data <- fixture("", "yes")
  data$awake_calm <- "yes"
  output <- analyze(data)
  expect_equal(output$normalized$data$sleep_state, "awake")
  expect_equal(output$normalized$data$behaviour, "yes")
  expect_equal(row_for(output$summary$patient)$behaviour_pct, 100)
})

test("Contradictory sleep evidence remains unknown and is flagged", {
  data <- fixture(c("awake", "asleep", "", "awake"))
  data$awake_calm <- c("", "yes", "yes", "")
  data$sleeping <- c("yes", "", "yes", "")
  output <- analyze(data)
  expect_equal(output$normalized$data$sleep_state, c("unknown", "unknown", "unknown", "awake"))
  expect_equal(output$normalized$issues$row[output$normalized$issues$code == "conflicting_sleep"], 1:3)
  expect_equal(row_for(output$summary$patient)$n_sleep_known, 1)
})

test("Unmapped primary codes and ambiguous fallback values are never guessed", {
  data <- fixture(c("other", "", " AWAKE "), c("other", "", " YES "))
  data$awake_calm <- c("yes", "yes", "")
  data$sleeping <- c("", "unexpected", "")
  output <- analyze(data)
  expect_equal(output$normalized$data$sleep_state, c("unknown", "unknown", "awake"))
  expect_equal(output$normalized$data$behaviour, c("unknown", "unknown", "yes"))
  expect_equal(row_for(output$summary$patient)$behaviour_pct, 100)
})

test("Baseline calculations contain no report-period observations", {
  data <- fixture(c(rep("asleep", 4), rep("awake", 4)),
                  timestamp = c(sprintf("2026-08-01T01:%02d:00Z", 0:3),
                                sprintf("2026-08-02T01:%02d:00Z", 0:3)))
  output <- analyze(data)$summary
  row <- row_for(output$baseline)
  expect_equal(row$baseline_n_observations, 4)
  expect_equal(row$report_n_observations, 4)
  expect_equal(row$baseline_sleep_pct, 100)
  expect_equal(row$report_sleep_pct, 0)
  expect_equal(row$sleep_change_pp, -100)
  expect_true(row$sleep_eligible)
  expect_equal(row_for(output$patient)$n_observations, 4)
  expect_equal(row_for(output$unit)$n_observations, 4)
})

test("Behaviour baseline differences use awake-known denominators in both periods", {
  data <- fixture(rep("awake", 8), c("yes", "yes", "no", "no", rep("no", 4)),
                  timestamp = c(sprintf("2026-08-01T01:%02d:00Z", 0:3),
                                sprintf("2026-08-02T01:%02d:00Z", 0:3)))
  row <- row_for(analyze(data)$summary$baseline)
  expect_equal(row$baseline_behaviour_pct, 50)
  expect_equal(row$report_behaviour_pct, 0)
  expect_equal(row$behaviour_change_pp, -50)
  expect_true(row$behaviour_eligible)
})

test("Baseline comparisons cannot borrow observations from another admission or unit", {
  for (field in c("episode_id", "unit")) {
    data <- fixture(c("asleep", "awake"), timestamp = c("2026-08-01T01:00:00Z", "2026-08-02T01:00:00Z"))
    data[[field]][1] <- paste0(data[[field]][1], "-OTHER")
    row <- row_for(analyze(data)$summary$baseline)
    expect_true(!row$sleep_eligible)
    expect_true(is.na(row$sleep_change_pp))
    expect_equal(row$sleep_status, "no matching baseline admission")
  }
})

test("Low report completeness suppresses baseline change without hiding recorded proportions", {
  data <- fixture(c("asleep", "asleep", "awake", ""),
                  timestamp = c("2026-08-01T01:00:00Z", "2026-08-01T01:01:00Z",
                                "2026-08-02T01:00:00Z", "2026-08-02T01:01:00Z"))
  output <- analyze(data)$summary
  row <- row_for(output$baseline)
  expect_equal(row$report_sleep_known_pct, 50)
  expect_equal(row_for(output$patient)$sleep_pct, 0)
  expect_true(!row$sleep_eligible)
  expect_true(is.na(row$sleep_change_pp))
  expect_true(grepl("report recorded completeness", row$sleep_status, fixed = TRUE))
})

test("Behaviour completeness independently suppresses its comparison", {
  data <- fixture(rep("awake", 3), c("no", "yes", ""),
                  timestamp = c("2026-08-01T01:00:00Z", "2026-08-02T01:00:00Z", "2026-08-02T01:01:00Z"))
  row <- row_for(analyze(data)$summary$baseline)
  expect_equal(row$report_behaviour_known_awake_pct, 50)
  expect_true(row$sleep_eligible)
  expect_true(!row$behaviour_eligible)
  expect_true(is.na(row$behaviour_change_pp))
})

test("Too few known baseline observations suppress a change even at full completeness", {
  data <- fixture(c("asleep", "awake", "awake"),
                  timestamp = c("2026-08-01T01:00:00Z", "2026-08-02T01:00:00Z", "2026-08-02T01:01:00Z"))
  row <- row_for(analyze(data, test_config(min_baseline_observations = 2))$summary$baseline)
  expect_equal(row$baseline_sleep_known_pct, 100)
  expect_true(!row$sleep_eligible)
  expect_true(is.na(row$sleep_change_pp))
  expect_equal(row$sleep_status, "insufficient baseline known observations")
})

test("Unconfigured baselines stay explicitly disabled", {
  output <- analyze(fixture("awake"), test_config(baseline_start = as.Date(NA), baseline_end = as.Date(NA)))
  expect_true(all(output$summary$baseline$sleep_status == "baseline disabled"))
  expect_true(all(is.na(output$summary$baseline$sleep_change_pp)))
})

test("A gap between baseline and report is not included in either period", {
  data <- fixture(c("asleep", "asleep", "awake"), timestamp = c("2026-08-01T01:00:00Z",
                         "2026-08-02T01:00:00Z", "2026-08-03T01:00:00Z"))
  output <- analyze(data, test_config(start_date = as.Date("2026-08-03"), end_date = as.Date("2026-08-03")))
  expect_equal(nrow(output$normalized$data), 2)
  expect_equal(row_for(output$summary$baseline)$baseline_n_observations, 1)
  expect_equal(row_for(output$summary$baseline)$report_n_observations, 1)
})

test("Hours estimates are off by default and explicitly standardized when enabled", {
  data <- fixture(c("asleep", "awake"))
  default <- analyze(data)$summary
  for (table in default) expect_true(!"standardized_sleep_hours" %in% names(table))
  enabled <- analyze(data, test_config(estimate_hours = TRUE))$summary
  expect_equal(row_for(enabled$patient)$standardized_sleep_hours, 12)
  expect_equal(row_for(enabled$patient, "Night")$standardized_sleep_hours, 4)
  expect_equal(row_for(enabled$unit)$standardized_sleep_hours, 12)
})

test("Source files with duplicate headers are rejected rather than silently selecting a column", {
  data <- fixture("awake")
  data$extra <- "asleep"
  names(data)[ncol(data)] <- "sleep_state"
  expect_error(analyze(data), "duplicat")
})

with_config_file <- function(changes, callback) {
  raw <- read.dcf(file.path(repo_root, "config", "site.example.dcf"))
  values <- as.list(raw[1, ])
  for (key in names(changes)) values[key] <- changes[key]
  path <- tempfile(fileext = ".dcf")
  on.exit(unlink(path), add = TRUE)
  write.dcf(as.data.frame(values, stringsAsFactors = FALSE), path, width = 100000L)
  callback(path)
}

test("Example site configuration parses with hours estimation disabled", {
  config <- read_monitoring_config(file.path(repo_root, "config", "site.example.dcf"))
  expect_true(!config$estimate_hours)
  expect_true(inherits(config$start_date, "Date"))
  expect_equal(sum((config$bands$end - config$bands$start) %% 1440), 1440)
})

test("Configuration rejects overlapping and incomplete time bands", {
  for (bands in c("A=00:00-13:00|B=12:00-24:00", "A=00:00-08:00|B=09:00-24:00")) {
    with_config_file(list(TimeBands = bands), function(path) expect_error(read_monitoring_config(path), "gaps|overlaps"))
  }
})

test("Configuration rejects unknown settings, ambiguous codes, and overlapping baseline dates", {
  with_config_file(list(UnexpectedSetting = "yes"), function(path) expect_error(read_monitoring_config(path), "Unknown"))
  with_config_file(list(AwakeCodes = "same", AsleepCodes = "SAME"), function(path) expect_error(read_monitoring_config(path), "disjoint"))
  with_config_file(list(StartDate = "2026-08-02", EndDate = "2026-08-02", BaselineStart = "2026-08-01", BaselineEnd = "2026-08-02"),
                   function(path) expect_error(read_monitoring_config(path), "earlier|nonoverlapping"))
})

test("CSV import preserves identifiers with leading zeroes", {
  path <- tempfile(fileext = ".csv")
  writeLines(c("patient_id,observation_id", "00123,000045"), path)
  imported <- read_monitoring_input(path)
  unlink(path)
  expect_equal(imported$patient_id, "00123")
  expect_equal(imported$observation_id, "000045")
})

test("HTML escaping protects text and attribute delimiters", {
  expect_equal(sbm_report_escape(c("<&>\"'", NA_character_)),
               c("&lt;&amp;&gt;&quot;&#39;", ""))
})

test("Chart data preserve missing days and hours as gaps, distinct from observed zero", {
  config <- test_config(end_date = as.Date("2026-08-04"))
  data <- fixture(c("awake", "asleep"), timestamp = c("2026-08-02T01:00:00Z", "2026-08-04T01:00:00Z"))
  output <- analyze(data, config)$summary
  daily <- sbm_report_chart_data(output$daily, "report_date", config)
  hourly <- sbm_report_chart_data(output$hourly, "hour", config)
  expect_equal(daily$sleep_pct, c(0, NA, 100))
  expect_equal(nrow(hourly), 24)
  expect_equal(hourly$sleep_pct[hourly$hour == 1], 50)
  expect_true(all(is.na(hourly$sleep_pct[hourly$hour != 1])))
})

test("CSV formula neutralization covers whitespace prefixes without changing numeric results", {
  text <- c("=1+1", "+1+1", "-1+1", "@SUM(A1)", "   =1+1", "\ttext", "\rtext", "\ntext", "ordinary", NA_character_)
  data <- data.frame(label = text, result = c(-50, 100, 0, NA, rep(2, 6)), stringsAsFactors = FALSE)
  safe <- sbm_report_csv_safe(data)
  expect_equal(safe$label[1:8], paste0("'", text[1:8]))
  expect_equal(safe$label[9], "ordinary")
  expect_true(is.na(safe$label[10]))
  expect_equal(safe$result, data$result)
  expect_true(is.numeric(safe$result))
})

with_report_directory <- function(callback) {
  output_dir <- tempfile("sbm-report-test-")
  on.exit(unlink(output_dir, recursive = TRUE), add = TRUE)
  callback(output_dir)
}

test("Generated report escapes source labels and exports safe summaries automatically", {
  with_report_directory(function(output_dir) {
    unit <- '<img src=x onerror="alert(1)"> & Sample'
    title <- '<script>alert("synthetic")</script>'
    data <- fixture(c("awake", "asleep"), patient = rep("=1+1", 2), unit = rep(unit, 2))
    config <- test_config(title = title)
    result <- write_monitoring_report(report_results(data, config), config, output_dir)
    expect_true(file.exists(result$html))
    expect_true(all(file.exists(result$csv)))
    html <- paste(readLines(result$html, warn = FALSE), collapse = "\n")
    expect_true(grepl(sbm_report_escape(title), html, fixed = TRUE))
    expect_true(grepl(sbm_report_escape(unit), html, fixed = TRUE))
    expect_true(!grepl(title, html, fixed = TRUE))
    expect_true(!grepl(unit, html, fixed = TRUE))
    expect_true(grepl("<svg", html, fixed = TRUE))
    expect_true(!grepl("SYN-O001", html, fixed = TRUE))
    exported <- read.csv(file.path(output_dir, "summary-patient.csv"), stringsAsFactors = FALSE)
    expect_true(all(exported$patient_id == "'=1+1"))
    expect_equal(exported$sleep_pct[exported$band == "Total"], 50)
    expect_true(!"observation_id" %in% names(exported))
  })
})

for (file in c("test_extended.R", "test_statistics.R", "test_raw_config.R"))
  source(file.path(repo_root, "tests", file))

failures <- Filter(function(result) !is.null(result$error), results)
cat("\n", length(results) - length(failures), "/", length(results), " tests passed\n", sep = "")
if (length(failures)) quit(status = 1L)
