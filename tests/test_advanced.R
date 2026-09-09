#!/usr/bin/env Rscript
# Standalone base-R tests for the research edition's highest-risk boundaries.
local({
  full <- commandArgs(trailingOnly = FALSE)
  script <- sub("^--file=", "", full[grepl("^--file=", full)])
  root <- if (length(script)) dirname(dirname(normalizePath(script[1L]))) else normalizePath(".")
  for (file in c("config.R", "analytics.R", "extended.R", "synthetic.R"))
    sys.source(file.path(root, "R", file), envir = environment())
  for (file in c("analysis.R", "report.R")) sys.source(file.path(root, "advanced", file), envir = environment())
  count <- 0L
  check <- function(name, code) {
    force(code); count <<- count + 1L; cat("PASS:", name, "\n")
  }
  fails <- function(code, pattern) {
    err <- tryCatch({ force(code); NULL }, error = identity)
    stopifnot(inherits(err, "error"), grepl(pattern, conditionMessage(err), fixed = TRUE))
  }
  policy <- advanced_policy(file.path(root, "advanced", "research-policy.dcf"))
  config <- read_monitoring_config(file.path(root, "config", "site.example.dcf"))
  config$start_date <- as.Date("2026-08-01"); config$end_date <- as.Date("2026-08-25")
  fixture <- function() {
    out <- expand.grid(patient_id = c("A", "B", "C", "D", "E"), day = 1:25,
      metric = c("Sleep", "Any recorded behaviour"), KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
    out$episode_id <- "1"; out$unit <- "W"; out$report_date <- as.Date("2026-08-01") + out$day - 1L
    out$rate_pct <- out$day * ifelse(out$metric == "Sleep", 2, 3)
    out$n_known <- 10L; out$completeness_pct <- 100; out$day <- NULL; out
  }
  demo <- function() data.frame(patient_id = c("A", "A", "Z"), episode_id = c("1", "2", "1"),
    age_at_admission = c("70", "80", ""), sex_recorded = c("Female", "Female", ""),
    diagnostic_group = c("Group A", "Group B", ""), stringsAsFactors = FALSE)
  obs <- data.frame(patient_id = c("A", "A", "B", "A"), episode_id = c("2", "1", "1", "1"),
    observation_id = c("o4", "o1", "o2", "o3"), stringsAsFactors = FALSE)
  check("demographic joins use both keys without reordering or multiplying observations", {
    joined <- join_demographics(obs, demo())
    stopifnot(nrow(joined$data) == 4L, identical(joined$data$observation_id, obs$observation_id),
      identical(joined$data$age_at_admission, c(80, 70, NA_real_, 70)),
      joined$data$age_band[3L] == "Unknown", !joined$data$demographic_match[3L],
      joined$audit$count[joined$audit$metric == "unused_demographic_rows"] == 1L,
      joined$audit$count[joined$audit$metric == "unmatched_patient_episodes"] == 1L)
  })
  check("duplicate and missing demographic keys are rejected even when unused", {
    fails(join_demographics(obs, rbind(demo(), demo()[3L, ])), "Duplicate patient and episode")
    bad <- demo(); bad$episode_id[3L] <- ""; fails(join_demographics(obs, bad), "requires patient and episode")
  })
  check("unknown ages stay unknown and invalid ages or DOB fields fail", {
    data <- demo(); data$age_at_admission <- c("", NA, "84")
    valid <- validate_demographics(data)
    stopifnot(identical(valid$age_band, c("Unknown", "Unknown", "75-84")))
    for (age in c("121", "-1", "71.5", "unknown", "Inf")) {
      data$age_at_admission[1L] <- age
      fails(validate_demographics(data), "whole number from 0 to 120")
    }
    data <- demo(); data$date_of_birth <- "1900-01-01"
    fails(validate_demographics(data), "dates of birth are not accepted")
  })
  check("small demographic cells suppress rates and denominators by contributing people", {
    current <- data.frame(patient_id = c("A", "A", "B", "C", "D", "E"),
      episode_id = c("1", "2", "1", "1", "1", "1"), unit = "W", report_date = as.Date("2026-08-15"),
      sleep_state = c("asleep", "awake", "awake", "awake", "unknown", "awake"),
      behaviour = c("no", "yes", "no", "unknown", "no", "yes"), age_band = "Unknown", sex_recorded = "Unknown", diagnostic_group = "Group A")
    cohorts <- advanced_cohorts(current, config, policy)
    stopifnot(all(is.na(cohorts$recorded_rate_pct)), all(is.na(cohorts$n_known)),
      all(cohorts$n_group_patients == 5), all(cohorts$n_contributing_patients[cohorts$metric == "Sleep"] == 4),
      all(cohorts$n_contributing_patients[cohorts$metric == "Any recorded behaviour"] == 3))
    current$sleep_state[5L] <- "awake"
    cohorts <- advanced_cohorts(current, config, policy)
    stopifnot(all(is.finite(cohorts$recorded_rate_pct[cohorts$metric == "Sleep"])),
      all(is.na(cohorts$recorded_rate_pct[cohorts$metric == "Any recorded behaviour"])))
  })
  check("holdout dates are fixed from config even when latest outcomes are missing", {
    daily <- fixture(); daily <- daily[daily$report_date <= as.Date("2026-08-19"), ]
    result <- advanced_backtest(daily, config, policy)
    stopifnot(result$holdout_start == as.Date("2026-08-12"), result$holdout_end == as.Date("2026-08-25"),
      all(result$paired_internal$target_date <= as.Date("2026-08-19")),
      all(result$paired_internal$history_end_date < result$paired_internal$target_date))
  })
  check("both methods share identical eligible targets and a hand-calculated MAE", {
    result <- advanced_backtest(fixture(), config, policy)
    sleep <- result$summary[result$summary$metric == "Sleep", ]
    behaviour <- result$summary[result$summary$metric == "Any recorded behaviour", ]
    stopifnot(identical(sleep$n_targets, c(70L, 70L)), identical(behaviour$n_targets, c(70L, 70L)),
      isTRUE(all.equal(sleep$mae_percentage_points, c(2, 8))),
      isTRUE(all.equal(behaviour$mae_percentage_points, c(3, 12))),
      sum(result$coverage$n_observed_targets[result$coverage$status == "eligible"]) == nrow(result$paired_internal))
  })
  check("target-day values and future values cannot leak into earlier predictions", {
    before <- advanced_backtest(fixture(), config, policy)$paired_internal
    changed <- fixture(); changed$rate_pct[changed$report_date >= as.Date("2026-08-16")] <- 99
    after <- advanced_backtest(changed, config, policy)$paired_internal
    keep <- before$target_date <= as.Date("2026-08-16")
    fields <- c("last_observed_day_pct", "trailing_seven_day_mean_pct", "history_start_date", "history_end_date")
    stopifnot(identical(before[keep, fields], after[keep, fields]))
  })
  check("missing next-day observations are not relabelled across gaps", {
    daily <- fixture(); daily <- daily[!(daily$patient_id == "A" & daily$report_date == as.Date("2026-08-15")), ]
    result <- advanced_backtest(daily, config, policy)$paired_internal
    stopifnot(!any(result$patient_id == "A" & result$target_date %in% as.Date(c("2026-08-15", "2026-08-16"))),
      all(result$target_date == result$origin_date + 1L))
  })
  check("history windows use seven calendar days, not seven available observations", {
    daily <- fixture(); daily <- daily[daily$report_date %in% as.Date(c("2026-08-01", "2026-08-02", "2026-08-03", "2026-08-20", "2026-08-21")), ]
    result <- advanced_backtest(daily, config, policy)
    stopifnot(nrow(result$paired_internal) == 0L,
      any(result$coverage$status == "insufficient past days within seven calendar days"))
  })
  check("patient, episode and unit histories remain isolated", {
    daily <- fixture()
    extra <- daily[daily$patient_id == "A" & daily$report_date >= as.Date("2026-08-14"), ]
    extra$episode_id <- "new"; extra$unit <- "new-unit"; extra$rate_pct <- 90
    result <- advanced_backtest(rbind(daily, extra), config, policy)$paired_internal
    new <- result[result$episode_id == "new", ]
    stopifnot(all(new$target_date >= as.Date("2026-08-17")), all(new$last_observed_day_pct == 90), all(new$trailing_seven_day_mean_pct == 90))
    other_unit <- extra; other_unit$episode_id <- "1"; other_unit$unit <- "other-unit"; other_unit$rate_pct <- 85
    result <- advanced_backtest(rbind(daily, other_unit), config, policy)$paired_internal
    new <- result[result$unit == "other-unit", ]
    stopifnot(all(new$target_date >= as.Date("2026-08-17")), all(new$last_observed_day_pct == 85))
  })
  check("poor daily quality excludes a shared target instead of using a stale last value", {
    daily <- fixture(); daily$n_known[daily$patient_id == "A" & daily$report_date == as.Date("2026-08-15")] <- 1L
    result <- advanced_backtest(daily, config, policy)
    stopifnot(!any(result$paired_internal$patient_id == "A" & result$paired_internal$target_date %in% as.Date(c("2026-08-15", "2026-08-16"))),
      length(unique(result$summary$n_targets)) == 1L)
  })
  check("tiny backtest samples retain counts but suppress errors", {
    daily <- fixture(); daily <- daily[daily$patient_id == "A", ]
    result <- advanced_backtest(daily, config, policy)
    stopifnot(all(result$summary$n_patients == 1L), all(result$summary$n_targets == 14L),
      all(is.na(result$summary$mae_percentage_points)))
  })
  check("duplicate daily keys and too-short report periods fail", {
    daily <- fixture(); fails(advanced_backtest(rbind(daily, daily[1L, ]), config, policy), "Duplicate daily target")
    short <- config; short$start_date <- as.Date("2026-08-20")
    fails(advanced_backtest(daily, short, policy), "all 14 predeclared holdout dates")
  })
  check("unknown outcomes never become zero and empty eligible samples are valid", {
    daily <- fixture(); daily$rate_pct <- NA_real_; daily$n_known <- 0L; daily$completeness_pct <- 0
    result <- advanced_backtest(daily, config, policy)
    stopifnot(nrow(result$paired_internal) == 0L, all(result$summary$n_targets == 0L),
      all(is.na(result$summary$mae_percentage_points)))
  })
  check("report output escapes HTML and spreadsheet formulas", {
    stopifnot(advanced_escape('<script>"x"</script>') == '&lt;script&gt;&quot;x&quot;&lt;/script&gt;')
    path <- tempfile(fileext = ".csv")
    advanced_csv(data.frame(label = c("=HYPERLINK(1)", " @bad", "safe"), value = c(-2, 3, 4)), path)
    exported <- read.csv(path, stringsAsFactors = FALSE)
    stopifnot(identical(exported$label, c("'=HYPERLINK(1)", "' @bad", "safe")), identical(exported$value, c(-2L, 3L, 4L)))
    unlink(path)
  })
  check("synthetic demographics align with all eight generated patient episodes", {
    input <- make_synthetic_observations()
    cfg <- read_monitoring_config(file.path(root, "config", "site.example.dcf"))
    normalized <- normalize_observations(input, cfg)
    joined <- join_demographics(normalized$data, make_synthetic_demographics())
    stopifnot(all(joined$data$demographic_match), nrow(joined$data) == nrow(normalized$data),
      nrow(unique(joined$data[c("patient_id", "episode_id")])) == 8L)
  })
  cat(count, "advanced research checks passed.\n")
})
