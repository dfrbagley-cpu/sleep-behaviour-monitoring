# Synthetic, deterministic regression checks. These verify implementation and
# safety gates; passing them does not establish inferential calibration.

statistics_fixture <- function() {
  rates <- c(rep(c(10, 20, 30, 40), 7L), rep(c(30, 40, 50, 60), 7L))
  data.frame(patient_id = "SYN-STAT-1", episode_id = "SYN-EPISODE-1",
    unit = "Sample Unit", report_date = seq(as.Date("2026-01-01"), as.Date("2026-02-25"), by = "day"),
    metric = "Sleep", n_yes = rates, n_known = 100L, n_eligible = 100L,
    rate_pct = rates, completeness_pct = 100, stringsAsFactors = FALSE)
}

statistics_config <- function(enabled = FALSE) {
  list(start_date = as.Date("2026-01-29"), end_date = as.Date("2026-02-25"),
    baseline_start = as.Date("2026-01-01"), baseline_end = as.Date("2026-01-28"),
    statistics_enabled = enabled)
}

test("HAC lag zero matches the hand-calculated contrast standard error", {
  actual <- sbm_hac_contrast(c(10, 20, 30, 40), c(20, 30, 40, 50), lag = 0L)
  # Residual sum of squares is 1000; OLS contrast variance is
  # (1000 / (8 - 2)) * (1/4 + 1/4) = 250/3.
  expect_equal(actual$effect_pp, 10)
  expect_equal(actual$standard_error_pp, sqrt(250 / 3))
  expect_equal(actual$p_value, 0.273321678292298)
  expect_equal(actual$ci_low_pp, -7.89194143717158)
  expect_equal(actual$ci_high_pp, 27.8919414371716)
})

test("HAC includes lagged covariance across the baseline and current boundary", {
  actual <- sbm_hac_contrast(c(10, 20, 30, 40), c(20, 30, 40, 50), lag = 1L)
  # Contrast-weighted residuals are 3.75,1.25,-1.25,-3.75,
  # -3.75,-1.25,1.25,3.75. Their squares sum to 62.5; lag-one
  # products sum to 29.6875. Bartlett(1)=1/2; adjusted variance
  # is (62.5 + 29.6875) * 8/6 = 1475/12.
  expect_equal(actual$standard_error_pp^2, 1475 / 12)
})

test("Experimental inference is off by default while descriptive effects remain", {
  config <- statistics_config()
  config$statistics_enabled <- NULL
  actual <- compute_monitoring_statistics(statistics_fixture(), config)
  expect_equal(actual$baseline_mean_pct, 25)
  expect_equal(actual$report_mean_pct, 45)
  expect_equal(actual$effect_pp, 20)
  expect_equal(actual$n_baseline_days, 28L)
  expect_equal(actual$n_report_days, 28L)
  expect_true(!actual$eligible)
  expect_true(all(is.na(unlist(actual[c("p_value", "p_adjusted", "ci_low_pp", "ci_high_pp", "standard_error_pp", "significant")]))))
  expect_true(grepl("experimental inference disabled", actual$status, fixed = TRUE))
})

test("Daily means give each day equal weight despite changing check counts", {
  data <- statistics_fixture()
  data$n_known[1] <- data$n_eligible[1] <- 1000L
  data$n_yes[1] <- 100L
  data <- data[-2L, ]
  actual <- compute_monitoring_statistics(data, statistics_config())
  baseline <- data[data$report_date < as.Date("2026-01-29"), ]
  expect_equal(actual$baseline_mean_pct, 680 / 27)
  expect_equal(actual$n_baseline_days, 27L)
  expect_equal(actual$n_report_days, 28L)
  expect_true(abs(actual$baseline_mean_pct - 100 * sum(baseline$n_yes) / sum(baseline$n_known)) > 1)
})

test("A missing calendar day is not compressed out of experimental testing", {
  actual <- compute_monitoring_statistics(statistics_fixture()[-8L, ], statistics_config(TRUE))
  expect_true(!actual$eligible)
  expect_true(is.na(actual$p_value) && is.na(actual$significant))
  expect_equal(actual$n_baseline_days, 27L)
  expect_true(grepl("missing calendar days", actual$status, fixed = TRUE))
})

test("Low daily field completeness suppresses inference without hiding observed change", {
  data <- statistics_fixture()
  data$n_eligible[3] <- 200L
  data$completeness_pct[3] <- 50
  actual <- compute_monitoring_statistics(data, statistics_config(TRUE))
  expect_true(!actual$eligible)
  expect_true(is.na(actual$p_value))
  expect_equal(actual$effect_pp, 20)
  expect_true(grepl("field completeness", actual$status, fixed = TRUE))
})

test("Sparse known daily denominators suppress inference even with complete fields", {
  data <- statistics_fixture()
  data$n_known[1] <- data$n_eligible[1] <- 2L
  data$n_yes[1] <- 1L
  data$rate_pct[1] <- 50
  actual <- compute_monitoring_statistics(data, statistics_config(TRUE))
  expect_true(!actual$eligible)
  expect_true(is.na(actual$p_value))
  expect_true(grepl("known eligible checks", actual$status, fixed = TRUE))
})

test("A constant period never creates a zero-uncertainty statistical flag", {
  data <- statistics_fixture()
  data$rate_pct[1:28] <- data$n_yes[1:28] <- 10
  actual <- compute_monitoring_statistics(data, statistics_config(TRUE))
  expect_equal(actual$effect_pp, 35)
  expect_true(!actual$eligible)
  expect_true(is.na(actual$standard_error_pp) && is.na(actual$p_adjusted) && is.na(actual$significant))
  expect_true(grepl("variation", actual$status, fixed = TRUE))
})

test("Holm keeps unavailable planned contrasts in the report comparison family", {
  data <- statistics_fixture()
  # A modest nonzero effect gives a nondegenerate adjustment to check.
  data$rate_pct[29:56] <- data$n_yes[29:56] <- data$rate_pct[29:56] - 19
  standalone <- compute_monitoring_statistics(data, statistics_config(TRUE))
  constant <- data
  constant$metric <- "Synthetic constant behaviour"
  constant$rate_pct <- constant$n_yes <- 10
  combined <- compute_monitoring_statistics(rbind(data, constant), statistics_config(TRUE))
  expect_equal(combined$family_size, c(2L, 2L))
  expect_equal(sum(combined$eligible), 1L)
  expect_equal(combined$p_adjusted[combined$eligible], min(1, 2 * standalone$p_value))
  expect_true(is.na(combined$significant[!combined$eligible]))
  expect_true(grepl("experimental", combined$status[combined$eligible], ignore.case = TRUE))
})

test("Rows from another episode do not fill an index episode baseline", {
  data <- statistics_fixture()
  data$episode_id[1:28] <- "SYN-OTHER-EPISODE"
  actual <- compute_monitoring_statistics(data, statistics_config(TRUE))
  expect_equal(nrow(actual), 1L)
  expect_equal(actual$n_baseline_days, 0L)
  expect_true(is.na(actual$effect_pp) && !actual$eligible)
  expect_true(grepl("no matching earlier data", actual$status, fixed = TRUE))
})

test("Statistics reject duplicate daily keys instead of silently double counting", {
  data <- statistics_fixture()
  expect_error(compute_monitoring_statistics(rbind(data, data[1, ]), statistics_config(TRUE)), "exactly one row")
})

test("Large check counts do not substitute for the configured number of days", {
  data <- statistics_fixture()[c(28, 29), ]
  data$n_known <- data$n_eligible <- 10000L
  data$n_yes <- data$rate_pct * 100
  config <- statistics_config(TRUE)
  config$baseline_start <- config$baseline_end <- as.Date("2026-01-28")
  config$start_date <- config$end_date <- as.Date("2026-01-29")
  actual <- compute_monitoring_statistics(data, config)
  expect_true(!actual$eligible)
  expect_true(is.na(actual$p_value))
  expect_true(grepl("at least 28 calendar days", actual$status, fixed = TRUE))
})

test("Nonadjacent windows and missing daily rates are explicitly unavailable", {
  data <- statistics_fixture()
  current <- data$report_date >= as.Date("2026-01-29")
  data$report_date[current] <- data$report_date[current] + 2
  data$n_yes[5] <- data$n_known[5] <- 0L
  data$rate_pct[5] <- NA_real_
  data$completeness_pct[5] <- 0
  config <- statistics_config(TRUE)
  config$start_date <- config$start_date + 2
  config$end_date <- config$end_date + 2
  actual <- compute_monitoring_statistics(data, config)
  expect_true(!actual$eligible)
  expect_equal(actual$n_baseline_days, 27L)
  expect_true(grepl("must be adjacent", actual$status, fixed = TRUE))
  expect_true(grepl("no usable rate", actual$status, fixed = TRUE))
})
