# EXPERIMENTAL daily contrasts; disabled in the reporting API by default.
# Finite-sample null simulations exposed inflated false-positive rates. See
# docs/STATISTICS.md. Neither the sample-size gates nor Holm correct that issue.
# Repeated point checks are never treated as
# independent subjects. Eligibility defaults are engineering settings, not
# clinically validated thresholds or a guarantee of valid inference.
# Newey-West: https://www.jstatsoft.org/v11/i10/
# Multiplicity: https://stat.ethz.ch/R-manual/R-devel/library/stats/html/p.adjust.html

sbm_hac_contrast <- function(baseline, report, lag = 7L, alpha = 0.05) {
  # This helper expects equally spaced, consecutive days; its caller enforces
  # calendar adjacency and complete eligible daily series before using it.
  if (!is.numeric(baseline) || !is.numeric(report) ||
      length(baseline) < 2L || length(report) < 2L ||
      any(!is.finite(c(baseline, report))))
    stop("HAC contrasts require two finite numeric daily series with at least two days each.", call. = FALSE)
  n <- length(baseline) + length(report)
  if (length(lag) != 1L || !is.numeric(lag) || !is.finite(lag) ||
      lag < 0 || lag != floor(lag) || lag >= n - 2L)
    stop("HAC lag must be a nonnegative integer smaller than the residual degrees of freedom.", call. = FALSE)
  if (length(alpha) != 1L || !is.numeric(alpha) || !is.finite(alpha) || alpha <= 0 || alpha >= 1)
    stop("alpha must be a number strictly between zero and one.", call. = FALSE)
  effect <- mean(report) - mean(baseline)
  unavailable <- list(effect_pp = effect, ci_low_pp = NA_real_, ci_high_pp = NA_real_,
    standard_error_pp = NA_real_, p_value = NA_real_, eligible = FALSE,
    status = "Not tested: insufficient within-period variation")
  epsilon <- sqrt(.Machine$double.eps)
  if (stats::var(baseline) <= epsilon || stats::var(report) <= epsilon) return(unavailable)
  y <- c(baseline, report)
  current <- c(rep(0, length(baseline)), rep(1, length(report)))
  x <- cbind(intercept = 1, current = current)
  bread <- solve(crossprod(x))
  beta <- drop(bread %*% crossprod(x, y))
  residual <- y - drop(x %*% beta)
  scores <- x * residual
  meat <- crossprod(scores)
  if (lag > 0L) for (k in seq_len(lag)) {
    cross_lag <- crossprod(scores[(k + 1L):n, , drop = FALSE], scores[seq_len(n - k), , drop = FALSE])
    meat <- meat + (1 - k / (lag + 1)) * (cross_lag + t(cross_lag))
  }
  covariance <- (bread %*% meat %*% bread) * n / (n - ncol(x))
  variance <- covariance[2L, 2L]
  if (!is.finite(variance) || variance <= epsilon) {
    unavailable$status <- "Not tested: insufficient estimated uncertainty"
    return(unavailable)
  }
  se <- sqrt(variance)
  critical <- stats::qnorm(1 - alpha / 2)
  list(effect_pp = effect, ci_low_pp = effect - critical * se,
    ci_high_pp = effect + critical * se, standard_error_pp = se,
    p_value = 2 * stats::pnorm(-abs(effect / se)), eligible = TRUE,
    status = "Tested; multiplicity adjustment pending")
}

compute_monitoring_statistics <- function(metric_daily, config) {
  required <- c("patient_id", "episode_id", "unit", "report_date", "metric",
    "n_yes", "n_known", "n_eligible", "rate_pct", "completeness_pct")
  if (!is.data.frame(metric_daily) || !all(required %in% names(metric_daily)))
    stop("Daily statistics input is missing required metric fields.", call. = FALSE)
  defaults <- list(statistics_enabled = FALSE, min_stat_days = 28L,
    min_stat_known_per_day = 6L, min_completeness_pct = 80, hac_lag = 7L, alpha = 0.05)
  settings <- lapply(names(defaults), function(name) if (is.null(config[[name]])) defaults[[name]] else config[[name]])
  names(settings) <- names(defaults)
  if (!is.logical(settings$statistics_enabled) || length(settings$statistics_enabled) != 1L || is.na(settings$statistics_enabled))
    stop("statistics_enabled must be TRUE or FALSE.", call. = FALSE)
  for (name in c("min_stat_days", "min_stat_known_per_day", "hac_lag")) {
    value <- settings[[name]]
    minimum <- if (name == "min_stat_days") 2L else if (name == "min_stat_known_per_day") 1L else 0L
    if (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value < minimum || value != floor(value))
      stop(name, " has an invalid integer setting.", call. = FALSE)
  }
  if (!is.numeric(settings$min_completeness_pct) || length(settings$min_completeness_pct) != 1L ||
      !is.finite(settings$min_completeness_pct) || settings$min_completeness_pct < 0 || settings$min_completeness_pct > 100)
    stop("min_completeness_pct must be between zero and 100.", call. = FALSE)
  if (!is.numeric(settings$alpha) || length(settings$alpha) != 1L || !is.finite(settings$alpha) ||
      settings$alpha <= 0 || settings$alpha >= 1)
    stop("alpha must be strictly between zero and one.", call. = FALSE)
  date_setting <- function(name, optional = FALSE) {
    value <- config[[name]]
    if (is.null(value) || (length(value) == 1L && is.na(value))) {
      if (optional) return(as.Date(NA))
      stop(name, " is required.", call. = FALSE)
    }
    if (length(value) != 1L) stop(name, " must be one date.", call. = FALSE)
    date <- tryCatch(as.Date(value), error = function(e) as.Date(NA))
    if (is.na(date)) stop(name, " must be a valid date.", call. = FALSE)
    date
  }
  start <- date_setting("start_date")
  end <- date_setting("end_date")
  bs <- date_setting("baseline_start", TRUE)
  be <- date_setting("baseline_end", TRUE)
  if (end < start || xor(is.na(bs), is.na(be)) || (!is.na(bs) && (be < bs || be >= start)))
    stop("Statistics require valid, nonoverlapping current and earlier baseline windows.", call. = FALSE)
  has_baseline <- !is.na(bs)
  data <- metric_daily
  data$report_date <- tryCatch(as.Date(data$report_date), error = function(e) rep(as.Date(NA), nrow(data)))
  keys <- c("patient_id", "episode_id", "unit", "metric")
  if (anyNA(data$report_date) || any(vapply(data[keys], function(x) anyNA(x) || any(!nzchar(as.character(x))), logical(1))))
    stop("Statistics require nonmissing dates and identifiers.", call. = FALSE)
  if (any(duplicated(data[c(keys, "report_date")])))
    stop("Statistics require exactly one row per patient, episode, unit, metric and reporting day.", call. = FALSE)
  for (name in c("n_yes", "n_known", "n_eligible")) {
    value <- data[[name]]
    if (!is.numeric(value) || any(!is.finite(value)) || any(value < 0 | value != floor(value)))
      stop("Daily metric counts must be finite nonnegative integers.", call. = FALSE)
  }
  if (any(data$n_yes > data$n_known | data$n_known > data$n_eligible))
    stop("Daily metric counts must satisfy yes <= known <= eligible.", call. = FALSE)
  for (name in c("rate_pct", "completeness_pct")) {
    value <- data[[name]]
    if (!is.numeric(value) || any(!is.na(value) & (!is.finite(value) | value < 0 | value > 100)))
      stop("Daily metric percentages must be within zero and 100 or missing.", call. = FALSE)
  }
  method <- "Daily mean difference; Newey-West HAC; Holm"
  empty <- data.frame(patient_id = character(), episode_id = character(), unit = character(), metric = character(),
    baseline_mean_pct = numeric(), report_mean_pct = numeric(), effect_pp = numeric(),
    ci_low_pp = numeric(), ci_high_pp = numeric(), standard_error_pp = numeric(), p_value = numeric(), p_adjusted = numeric(),
    n_baseline_days = integer(), n_report_days = integer(), eligible = logical(), significant = logical(),
    status = character(), method = character(), hac_lag = integer(), family_size = integer(), stringsAsFactors = FALSE)
  targets <- unique(data[data$report_date >= start & data$report_date <= end, keys, drop = FALSE])
  if (!nrow(targets)) return(empty)
  available_mean <- function(x) if (any(is.finite(x))) mean(x[is.finite(x)]) else NA_real_
  row_list <- vector("list", nrow(targets))
  for (i in seq_len(nrow(targets))) {
    matches <- rep(TRUE, nrow(data))
    for (key in keys) matches <- matches & data[[key]] == targets[[key]][i]
    subject <- data[matches, , drop = FALSE]
    subject <- subject[order(subject$report_date), , drop = FALSE]
    report <- subject[subject$report_date >= start & subject$report_date <= end, , drop = FALSE]
    baseline <- if (has_baseline) subject[subject$report_date >= bs & subject$report_date <= be, , drop = FALSE] else subject[FALSE, , drop = FALSE]
    base_mean <- available_mean(baseline$rate_pct)
    report_mean <- available_mean(report$rate_pct)
    out <- data.frame(targets[i, , drop = FALSE], baseline_mean_pct = base_mean,
      report_mean_pct = report_mean, effect_pp = report_mean - base_mean,
      ci_low_pp = NA_real_, ci_high_pp = NA_real_, standard_error_pp = NA_real_,
      p_value = NA_real_, p_adjusted = NA_real_,
      n_baseline_days = sum(is.finite(baseline$rate_pct)), n_report_days = sum(is.finite(report$rate_pct)),
      eligible = FALSE, significant = NA, status = "Not tested", method = method,
      hac_lag = as.integer(settings$hac_lag), family_size = nrow(targets), stringsAsFactors = FALSE)
    reasons <- character()
    if (!settings$statistics_enabled) reasons <- c(reasons, "experimental inference disabled")
    if (!has_baseline) reasons <- c(reasons, "no baseline period configured")
    if (has_baseline) {
      n_base_expected <- as.integer(be - bs) + 1L
      n_report_expected <- as.integer(end - start) + 1L
      if (be + 1 != start) reasons <- c(reasons, "baseline and report windows must be adjacent")
      if (n_base_expected < settings$min_stat_days || n_report_expected < settings$min_stat_days)
        reasons <- c(reasons, paste0("each period needs at least ", settings$min_stat_days, " calendar days"))
      if (nrow(baseline) != n_base_expected || nrow(report) != n_report_expected)
        reasons <- c(reasons, "missing calendar days in one or both periods")
      if (!nrow(baseline)) reasons <- c(reasons, "no matching earlier data for this person, episode and unit")
      selected <- rbind(baseline, report)
      if (any(!is.finite(selected$rate_pct))) reasons <- c(reasons, "one or more days have no usable rate")
      if (any(selected$n_known < settings$min_stat_known_per_day))
        reasons <- c(reasons, paste0("each day needs at least ", settings$min_stat_known_per_day, " known eligible checks"))
      if (any(!is.finite(selected$completeness_pct) | selected$completeness_pct < settings$min_completeness_pct))
        reasons <- c(reasons, paste0("one or more days are below ", settings$min_completeness_pct, "% field completeness"))
      if (settings$hac_lag >= nrow(selected) - 2L)
        reasons <- c(reasons, "too few days for the configured HAC lag")
    }
    if (length(reasons)) {
      out$status <- paste0("Not tested: ", paste(unique(reasons), collapse = "; "))
    } else {
      contrast <- sbm_hac_contrast(baseline$rate_pct, report$rate_pct, settings$hac_lag, settings$alpha)
      for (name in names(contrast)) out[[name]] <- contrast[[name]]
    }
    row_list[[i]] <- out
  }
  result <- do.call(rbind, row_list)
  rownames(result) <- NULL
  tested <- which(result$eligible & is.finite(result$p_value))
  if (length(tested)) {
    # The entire planned family remains in n, including unavailable contrasts.
    # CIs above are pointwise (1-alpha) intervals, not Holm-adjusted intervals.
    result$p_adjusted[tested] <- stats::p.adjust(result$p_value[tested], method = "holm", n = nrow(result))
    result$significant[tested] <- result$p_adjusted[tested] < settings$alpha
    result$status[tested] <- ifelse(result$significant[tested], "Experimental adjusted-p flag", "No experimental adjusted-p flag")
  }
  result[, names(empty), drop = FALSE]
}
