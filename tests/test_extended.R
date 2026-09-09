# Source after R/extended.R and the helpers in tests/run_tests.R, before that
# runner collects failures. All fixtures are constructed, small, and independent
# of the demo's number of patients or date range.

extended_fixture <- function() {
  admission <- function(patient, episode, values, unit = "W", day = 2L) {
    data.frame(observation_id = paste(patient, episode, day, seq_along(values), sep = "-"),
      patient_id = patient, episode_id = episode, unit = unit,
      observed_at = sprintf("2026-08-%02dT%02d:00:00Z", day, seq_along(values) - 1L),
      sleep_state = "awake", behaviour = values, awake_calm = "", sleeping = "",
      agitation = values, stringsAsFactors = FALSE)
  }
  do.call(rbind, list(admission("A", "1", c("yes", "no", "no", "no")),
    admission("A", "2", rep("yes", 4)), admission("B", "1", rep("no", 4)),
    admission("B", "2", rep("yes", 12)), admission("C", "1", c("yes", "yes", "no", "no")),
    admission("D", "1", rep("yes", 4)), admission("E", "1", rep("yes", 4), "OTHER")))
}

extended_config <- function(...) {
  config <- test_config(units = "W", patients = "A", min_completeness_pct = 50,
    min_peer_patients = 3L, behaviour_columns = c(Agitation = "agitation"))
  for (key in names(list(...))) config[[key]] <- list(...)[[key]]
  config
}

extended_result <- function(input = extended_fixture(), config = extended_config()) {
  extend_monitoring_analysis(input, normalize_observations(input, config), config)
}

extended_pick <- function(table, metric = "Any recorded behaviour", episode = "1", band = NULL) {
  keep <- table$patient_id == "A" & table$episode_id == episode & table$metric == metric
  if (!is.null(band)) keep <- keep & table$band == band
  result <- table[keep, , drop = FALSE]
  expect_equal(nrow(result), 1L)
  result
}

test("Normalization retains same-unit peers before applying a patient selection", {
  normalized <- normalize_observations(extended_fixture(), extended_config())
  expect_equal(unique(normalized$data$patient_id), "A")
  expect_equal(nrow(normalized$data), 8L)
  expect_equal(sort(unique(normalized$reference_data$patient_id)), c("A", "B", "C", "D"))
  expect_equal(nrow(normalized$reference_data), 32L)
  expect_true(all(normalized$reference_data$unit == "W"))
})

test("Peer rates exclude every index-person admission and give admissions equal weight", {
  row <- extended_pick(extended_result()$peer_comparisons)
  # Other-person admission rates are 0, 100, 50, 100. The 12-observation
  # admission has the same weight as the four-observation admissions.
  expect_equal(row$report_rate_pct, 25)
  expect_equal(row$peer_mean_pct, 62.5)
  expect_equal(row$difference_pp, -37.5)
  expect_equal(row$n_peer_admissions, 4L)
  expect_equal(row$n_peer_patients, 3L)
  expect_equal(row$status, "eligible")
  expect_equal(row$peer_median_pct, 75)
  expect_equal(row$peer_p25_pct, 37.5)
  expect_equal(row$peer_p75_pct, 100)
  expect_equal(row$percentile_midrank, 25)
  expect_true(grepl("No adjustment", row$interpretation, fixed = TRUE))
})

test("A peer percentile places an exact tie at its midrank", {
  row <- extended_pick(extended_result()$peer_comparisons, metric = "Sleep")
  expect_equal(row$report_rate_pct, 0)
  expect_equal(row$peer_mean_pct, 0)
  expect_equal(row$percentile_midrank, 50)
})

test("Peer references include only the report period even when baseline is available", {
  input <- extended_fixture()
  old <- input[input$patient_id == "B", , drop = FALSE]
  old$observation_id <- paste0(old$observation_id, "-baseline")
  old$observed_at <- sub("2026-08-02", "2026-08-01", old$observed_at, fixed = TRUE)
  old$behaviour <- old$agitation <- "no"
  input <- rbind(input, old)
  output <- extended_result(input)
  row <- extended_pick(output$peer_comparisons)
  expect_equal(row$peer_mean_pct, 62.5)
  expect_equal(row$n_peer_admissions, 4L)
  expect_true(any(output$reference_metric_daily$report_date == as.Date("2026-08-01")))
  expect_true(all(output$metric_daily$patient_id == "A"))
})

test("Daily metric records preserve baseline dates and category-specific unknowns", {
  input <- extended_fixture()
  input$agitation[1:4] <- c("yes", "no", "", "PRIVATE-UNMAPPED-CELL")
  baseline <- input[1:4, , drop = FALSE]
  baseline$observation_id <- paste0(baseline$observation_id, "-baseline")
  baseline$observed_at <- sub("2026-08-02", "2026-08-01", baseline$observed_at, fixed = TRUE)
  baseline$agitation <- "yes"
  input <- rbind(input, baseline)
  output <- extended_result(input)
  current <- output$metric_daily[output$metric_daily$report_date == as.Date("2026-08-02"), , drop = FALSE]
  row <- extended_pick(current, "Agitation")
  expect_equal(row$n_yes, 1)
  expect_equal(row$n_known, 2)
  expect_equal(row$n_eligible, 4)
  expect_equal(row$rate_pct, 50)
  expect_equal(row$completeness_pct, 50)
  expect_true(inherits(output$metric_daily$report_date, "Date"))
  expect_true(any(output$metric_daily$report_date == as.Date("2026-08-01")))
  expect_true(all(output$behaviour_daily$report_date == as.Date("2026-08-02")))
  expect_true(all(output$metric_daily$n_yes <= output$metric_daily$n_known))
  expect_true(all(output$metric_daily$n_known <= output$metric_daily$n_eligible))
  expect_equal(sort(output$issues$code), c("missing_detailed_behaviour", "unmapped_detailed_behaviour"))
  expect_true(!any(grepl("PRIVATE-UNMAPPED-CELL", output$issues$message, fixed = TRUE)))
})

test("Detailed behaviour rates exclude asleep and unknown-sleep observations", {
  input <- extended_fixture()
  input$sleep_state[1:4] <- c("awake", "asleep", "", "awake")
  input$agitation[1:4] <- c("yes", "yes", "yes", "no")
  row <- extended_pick(extended_result(input)$behaviour, "Agitation", band = "Total")
  expect_equal(row$n_yes, 1)
  expect_equal(row$n_known, 2)
  expect_equal(row$n_eligible, 2)
  expect_equal(row$rate_pct, 50)
  expect_equal(row$completeness_pct, 100)
  issues <- extended_result(input)$issues
  expect_equal(sort(issues$row[issues$code == "detailed_behaviour_excluded"]), 2:3)
})

test("Detail diagnostics remain within the patient-selected source rows", {
  input <- extended_fixture()
  input$agitation[] <- "PRIVATE-UNMAPPED-CELL"
  normalized <- normalize_observations(input, extended_config())
  output <- extend_monitoring_analysis(input, normalized, extended_config())
  expect_equal(sort(output$issues$row), sort(normalized$data$source_row))
  expect_true(all(output$issues$code == "unmapped_detailed_behaviour"))
  expect_true(!any(grepl("PRIVATE-UNMAPPED-CELL", output$issues$message, fixed = TRUE)))
})

test("Distinct eligible people govern peer suppression despite repeated admissions", {
  output <- extended_result(config = extended_config(min_peer_patients = 4L))
  row <- extended_pick(output$peer_comparisons)
  expect_equal(row$n_peer_admissions, 4L)
  expect_equal(row$n_peer_patients, 3L)
  expect_equal(row$status, "insufficient eligible peer patients")
  for (column in c("peer_mean_pct", "peer_median_pct", "peer_p25_pct", "peer_p75_pct",
                   "difference_pp", "percentile_midrank")) expect_true(is.na(row[[column]]))
})

test("Peers without an awake-known denominator cannot dilute behaviour averages", {
  input <- extended_fixture()
  input$sleep_state[input$patient_id == "D"] <- "asleep"
  output <- extended_result(input)
  row <- extended_pick(output$peer_comparisons)
  expect_equal(row$n_peer_admissions, 3L)
  expect_equal(row$n_peer_patients, 2L)
  expect_true(is.na(row$peer_mean_pct))
  expect_equal(extended_pick(output$peer_comparisons, "Sleep")$status, "eligible")
})

test("Known-observation and completeness thresholds apply separately to each metric", {
  input <- extended_fixture()
  input$agitation[input$patient_id == "D"] <- c("yes", "", "", "")
  output <- extended_result(input)
  expect_equal(extended_pick(output$peer_comparisons, "Agitation")$n_peer_patients, 2L)
  expect_equal(extended_pick(output$peer_comparisons)$n_peer_patients, 3L)
  input$agitation[1:4] <- c("yes", "", "", "")
  row <- extended_pick(extended_result(input)$peer_comparisons, "Agitation")
  expect_equal(row$status, "report recorded completeness below minimum")
  expect_true(is.na(row$peer_mean_pct))
  row <- extended_pick(extended_result(config = extended_config(min_baseline_observations = 5L))$peer_comparisons)
  expect_equal(row$status, "insufficient report known observations")
  expect_true(is.na(row$peer_mean_pct))
})

test("Missing reference scope suppresses peer comparison rather than guessing the ward", {
  input <- extended_fixture()
  config <- extended_config(patients = character())
  normalized <- normalize_observations(input, config)
  normalized$reference_data <- NULL
  output <- extend_monitoring_analysis(input, normalized, config)
  expect_true(all(output$peer_comparisons$n_peer_patients == 0L))
  expect_true(all(is.na(output$peer_comparisons$peer_mean_pct)))
  expect_true(nrow(output$behaviour) > 0L)
})

test("Unconfigured detailed behaviours remain optional and absent columns are rejected", {
  output <- extended_result(config = extended_config(behaviour_columns = character()))
  expect_equal(sort(unique(output$metric_daily$metric)), c("Any recorded behaviour", "Sleep"))
  expect_equal(unique(output$behaviour$metric), "Any recorded behaviour")
  expect_error(extended_result(config = extended_config(behaviour_columns = c(Agitation = "missing"))), "absent")
})

test("Malformed detailed behaviour mappings fail before any results are produced", {
  malformed <- list("agitation", list(Agitation = "agitation"), c(Agitation = 1),
    c(Agitation = NA_character_), setNames("agitation", NA_character_),
    setNames("agitation", ""), c(Agitation = ""), c(Sleep = "agitation"),
    c("Any recorded behaviour" = "agitation"),
    setNames(c("agitation", "behaviour"), c("Agitation", "AGITATION")),
    c(Agitation = "agitation", Distress = "agitation"),
    setNames("agitation", "Bad\nlabel"))
  for (mapping in malformed)
    expect_error(extended_result(config = extended_config(behaviour_columns = mapping)))
})

test("Invalid peer display thresholds fail explicitly", {
  for (value in list(0, -1, 1.5, NA_real_, Inf, "3", c(3, 4)))
    expect_error(extended_result(config = extended_config(min_peer_patients = value)), "positive integer")
})
