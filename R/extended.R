# Behaviour-specific summaries and descriptive, other-person ward comparisons.
# Each flag is an independently recorded yes/no field; categories may overlap.
# Peer daily records remain internal so a patient-selected export cannot expose
# another person's underlying observations.

sbm_extended_mapping <- function(input, config) {
  mapping <- config$behaviour_columns
  if (is.null(mapping) || !length(mapping)) return(setNames(character(), character()))
  if (!is.character(mapping) || is.null(names(mapping)) ||
      anyNA(mapping) || anyNA(names(mapping)))
    stop("behaviour_columns must be a named character vector of labels and source columns.", call. = FALSE)
  labels <- trimws(names(mapping))
  columns <- trimws(unname(mapping))
  if (any(!nzchar(labels)) || any(!nzchar(columns)) ||
      any(grepl("[[:cntrl:]]", labels)) || any(grepl("[[:cntrl:]]", columns)) ||
      anyDuplicated(tolower(labels)) || anyDuplicated(columns) ||
      any(tolower(labels) %in% c("sleep", "any recorded behaviour")))
    stop("Detailed behaviour labels and columns must be nonblank and unique; Sleep and Any recorded behaviour are reserved labels.", call. = FALSE)
  if (any(!columns %in% names(input)))
    stop("A requested detailed behaviour source column is absent from the input.", call. = FALSE)
  setNames(columns, labels)
}

sbm_extended_thresholds <- function(config) {
  count <- function(value, fallback, name) {
    if (is.null(value)) value <- fallback
    if (length(value) != 1L || !is.numeric(value) || !is.finite(value) ||
        value < 1 || value != floor(value))
      stop(paste(name, "must be a positive integer."), call. = FALSE)
    value
  }
  minimum <- count(config$min_baseline_observations, 10L, "min_baseline_observations")
  peers <- count(config$min_peer_patients, 3L, "min_peer_patients")
  completeness <- config$min_completeness_pct
  if (is.null(completeness)) completeness <- 80
  if (length(completeness) != 1L || !is.numeric(completeness) ||
      !is.finite(completeness) || completeness < 0 || completeness > 100)
    stop("min_completeness_pct must be between 0 and 100.", call. = FALSE)
  list(minimum = minimum, peers = peers, completeness = completeness)
}

sbm_extended_states <- function(input, data, mapping, config) {
  required <- c("patient_id", "episode_id", "unit", "report_date", "band",
                "sleep_state", "behaviour", "source_row")
  if (!is.data.frame(data) || !all(required %in% names(data)))
    stop("Extended analytics require normalized observations with source-row indices.", call. = FALSE)
  if (!is.numeric(data$source_row) || anyNA(data$source_row) ||
      any(data$source_row < 1 | data$source_row > nrow(input) |
          data$source_row != floor(data$source_row)))
    stop("Normalized source-row indices must refer to the supplied input.", call. = FALSE)
  states <- list("Sleep" = data$sleep_state,
                 "Any recorded behaviour" = data$behaviour)
  yes <- sbm_codes(config$codes$behaviour_yes)
  no <- sbm_codes(config$codes$behaviour_no)
  if (!length(yes) || !length(no) || any(!nzchar(c(yes, no))) || length(intersect(yes, no)))
    stop("Behaviour yes/no codes must be nonempty and disjoint.", call. = FALSE)
  issues <- data.frame(row = integer(), code = character(), message = character(), stringsAsFactors = FALSE)
  add_issue <- function(mask, code, message) {
    if (any(mask)) issues <<- rbind(issues, data.frame(row = data$source_row[mask],
      code = code, message = message, stringsAsFactors = FALSE))
  }
  for (label in names(mapping)) {
    raw <- tolower(sbm_text(input[[mapping[[label]]]][data$source_row]))
    state <- rep("unknown", nrow(data))
    state[raw %in% yes] <- "yes"
    state[raw %in% no] <- "no"
    states[[label]] <- state
    # Labels are configuration metadata. Source cell values are never included
    # in errors or issues, even when an unexpected code appears in the input.
    add_issue(!nzchar(raw), "missing_detailed_behaviour",
      paste0(label, ": value is missing; only explicit codes establish yes or no."))
    add_issue(nzchar(raw) & state == "unknown", "unmapped_detailed_behaviour",
      paste0(label, ": code is unmapped; behaviour is unknown."))
    add_issue(state == "yes" & data$sleep_state != "awake", "detailed_behaviour_excluded",
      paste0(label, ": recorded yes is outside the confirmed-awake denominator."))
  }
  list(states = states, issues = issues)
}

sbm_extended_counts <- function(data, states, metric, indices) {
  sleep <- data$sleep_state[indices]
  state <- states[[metric]][indices]
  if (metric == "Sleep") {
    eligible <- rep(TRUE, length(indices))
    known <- state %in% c("awake", "asleep")
    yes <- state == "asleep"
  } else {
    eligible <- sleep == "awake"
    known <- eligible & state %in% c("yes", "no")
    yes <- eligible & state == "yes"
  }
  n_eligible <- sum(eligible)
  n_known <- sum(known)
  n_yes <- sum(yes)
  data.frame(n_yes = n_yes, n_known = n_known, n_eligible = n_eligible,
    rate_pct = sbm_percent(n_yes, n_known),
    completeness_pct = sbm_percent(n_known, n_eligible))
}

sbm_extended_summary <- function(data, states, keys, metrics, bands = NULL) {
  output <- list()
  j <- 0L
  groups <- sbm_group_indices(data, keys)
  for (indices in groups) {
    for (band in if (is.null(bands)) "Total" else bands) {
      selected <- if (band == "Total") indices else indices[data$band[indices] == band]
      for (metric in metrics) {
        j <- j + 1L
        row <- data[indices[1L], keys, drop = FALSE]
        if (!is.null(bands)) row$band <- band
        row$metric <- metric
        output[[j]] <- cbind(row, sbm_extended_counts(data, states, metric, selected))
      }
    }
  }
  if (length(output)) result <- do.call(rbind, output)
  else {
    result <- data[FALSE, keys, drop = FALSE]
    if (!is.null(bands)) result$band <- character()
    result$metric <- character()
    result$n_yes <- result$n_known <- result$n_eligible <- integer()
    result$rate_pct <- result$completeness_pct <- numeric()
  }
  rownames(result) <- NULL
  result
}

sbm_extended_peer_comparisons <- function(own, reference, thresholds) {
  result <- own[c("patient_id", "episode_id", "unit", "metric")]
  result$report_rate_pct <- own$rate_pct
  result$report_n_yes <- own$n_yes
  result$report_n_known <- own$n_known
  result$report_n_eligible <- own$n_eligible
  result$report_completeness_pct <- own$completeness_pct
  result$peer_mean_pct <- result$peer_median_pct <- result$peer_p25_pct <- result$peer_p75_pct <-
    result$difference_pp <- result$percentile_midrank <- rep(NA_real_, nrow(own))
  result$n_peer_admissions <- result$n_peer_patients <- integer(nrow(own))
  result$status <- rep("eligible", nrow(own))
  result$interpretation <- rep(paste("Descriptive comparison with other patients on the same ward in the report period;",
    "each admission rate pools its known observations, and peer admissions have equal weight.",
    "No adjustment for case mix or treatment; no significance test."), nrow(own))
  reference_ok <- reference$n_known >= thresholds$minimum &
    !is.na(reference$completeness_pct) & reference$completeness_pct >= thresholds$completeness &
    is.finite(reference$rate_pct)
  for (i in seq_len(nrow(own))) {
    # Exclude the entire index person, including every other admission. An
    # admission-only exclusion would contaminate the person's peer comparison.
    peer <- reference[reference_ok & reference$unit == own$unit[i] &
      reference$metric == own$metric[i] & reference$patient_id != own$patient_id[i], , drop = FALSE]
    result$n_peer_admissions[i] <- nrow(peer)
    result$n_peer_patients[i] <- length(unique(peer$patient_id))
    status <- if (own$n_known[i] < thresholds$minimum || !is.finite(own$rate_pct[i]))
      "insufficient report known observations"
    else if (is.na(own$completeness_pct[i]) || own$completeness_pct[i] < thresholds$completeness)
      "report recorded completeness below minimum"
    else if (result$n_peer_patients[i] < thresholds$peers)
      "insufficient eligible peer patients"
    else "eligible"
    result$status[i] <- status
    if (status != "eligible") next
    peer_rates <- peer$rate_pct
    result$peer_mean_pct[i] <- mean(peer_rates)
    peer_quantiles <- unname(stats::quantile(peer_rates, probs = c(0.25, 0.5, 0.75), type = 7))
    result$peer_p25_pct[i] <- peer_quantiles[1L]
    result$peer_median_pct[i] <- peer_quantiles[2L]
    result$peer_p75_pct[i] <- peer_quantiles[3L]
    result$difference_pp[i] <- own$rate_pct[i] - result$peer_mean_pct[i]
    result$percentile_midrank[i] <- 100 * (sum(peer_rates < own$rate_pct[i]) +
      0.5 * sum(peer_rates == own$rate_pct[i])) / length(peer_rates)
  }
  rownames(result) <- NULL
  result
}

extend_monitoring_analysis <- function(input, normalized, config) {
  if (!is.data.frame(input) || anyDuplicated(names(input)))
    stop("Extended analytics require source input with unique column names.", call. = FALSE)
  if (!is.list(normalized) || is.data.frame(normalized) || is.null(normalized$data))
    stop("Extended analytics require the normalization result.", call. = FALSE)
  mapping <- sbm_extended_mapping(input, config)
  thresholds <- sbm_extended_thresholds(config)
  window <- sbm_date_window(config)
  bands <- c(as.character(sbm_check_bands(config$bands)$name), "Total")
  target <- normalized$data
  reference <- normalized$reference_data
  # A missing ward reference must not silently turn selected patients into the
  # complete ward population. Old callers can still obtain descriptive values,
  # but every peer comparison is suppressed until normalization supplies it.
  if (is.null(reference)) reference <- target[FALSE, , drop = FALSE]
  target_parsed <- sbm_extended_states(input, target, mapping, config)
  same_reference <- identical(reference$source_row, target$source_row)
  reference_parsed <- if (same_reference) target_parsed else sbm_extended_states(input, reference, mapping, config)
  metrics <- names(target_parsed$states)
  behaviour_metrics <- setdiff(metrics, "Sleep")
  keys <- c("patient_id", "episode_id", "unit")
  daily_keys <- c(keys, "report_date")
  metric_daily <- sbm_extended_summary(target, target_parsed$states, daily_keys, metrics)
  reference_metric_daily <- if (same_reference) metric_daily else sbm_extended_summary(reference, reference_parsed$states, daily_keys, metrics)
  in_report <- target$report_date >= window$start & target$report_date <= window$end
  current <- target[in_report, , drop = FALSE]
  current_states <- lapply(target_parsed$states, `[`, in_report)
  reference_current <- reference$report_date >= window$start & reference$report_date <= window$end
  reference_rows <- reference[reference_current, , drop = FALSE]
  reference_states <- lapply(reference_parsed$states, `[`, reference_current)
  own_totals <- sbm_extended_summary(current, current_states, keys, metrics)
  peer_totals <- sbm_extended_summary(reference_rows, reference_states, keys, metrics)
  behaviour <- sbm_extended_summary(current, current_states, keys, behaviour_metrics, bands)
  behaviour_daily <- metric_daily[metric_daily$metric %in% behaviour_metrics &
    metric_daily$report_date >= window$start & metric_daily$report_date <= window$end, , drop = FALSE]
  issues <- target_parsed$issues
  issues <- issues[order(issues$row, issues$code, issues$message), , drop = FALSE]
  rownames(behaviour_daily) <- rownames(issues) <- NULL
  list(behaviour = behaviour, behaviour_daily = behaviour_daily,
    peer_comparisons = sbm_extended_peer_comparisons(own_totals, peer_totals, thresholds),
    metric_daily = metric_daily, reference_metric_daily = reference_metric_daily,
    issues = issues)
}
