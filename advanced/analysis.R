# Research preparation and retrospective evaluation. Uses the shared normalized
# observation definitions. No demographic model or future clinical forecasts.

advanced_policy <- function(path) {
  raw <- read.dcf(path, all = TRUE)
  fields <- c("HoldoutDays", "TrailingCalendarDays", "MinHistoryDays", "MinKnownPerDay", "MinCompletenessPct", "MinGroupPatients")
  if (nrow(raw) != 1L || !setequal(names(raw), fields))
    stop("Research policy requires exactly the six fields in research-policy.dcf.", call. = FALSE)
  values <- suppressWarnings(as.numeric(unlist(raw[1, fields], use.names = FALSE)))
  if (any(!is.finite(values)) || any(values != floor(values)))
    stop("Research policy settings must be finite integers.", call. = FALSE)
  result <- as.list(setNames(values, fields))
  if (result$HoldoutDays != 14 || result$TrailingCalendarDays != 7 ||
      result$MinHistoryDays < 1 || result$MinHistoryDays > 7 || result$MinKnownPerDay < 1 ||
      result$MinCompletenessPct < 0 || result$MinCompletenessPct > 100 || result$MinGroupPatients < 3)
    stop("Use 14 holdout dates, a 7-calendar-day history, 1..7 history days, positive known counts, 0..100 completeness, and at least 3 group patients.", call. = FALSE)
  result
}

advanced_key <- function(data, fields) {
  # Core identifiers and demographic keys reject the separator/control characters.
  do.call(paste, c(lapply(data[fields], as.character), sep = "\034"))
}

validate_demographics <- function(data) {
  required <- c("patient_id", "episode_id", "age_at_admission", "sex_recorded", "diagnostic_group")
  if (!is.data.frame(data) || anyDuplicated(names(data)) || !setequal(names(data), required))
    stop("Demographics requires only patient_id, episode_id, age_at_admission, sex_recorded and diagnostic_group; dates of birth are not accepted.", call. = FALSE)
  data <- data[required]
  for (field in required) data[[field]] <- sbm_text(data[[field]])
  if (any(vapply(data, function(x) any(grepl("[[:cntrl:]]", x)), logical(1))))
    stop("Demographic fields must not contain control characters.", call. = FALSE)
  if (any(!nzchar(data$patient_id) | !nzchar(data$episode_id)))
    stop("Every demographic row requires patient and episode identifiers.", call. = FALSE)
  if (anyDuplicated(advanced_key(data, c("patient_id", "episode_id"))))
    stop("Duplicate patient and episode demographic keys; reconcile them before analysis.", call. = FALSE)
  age_text <- data$age_at_admission
  age <- suppressWarnings(as.numeric(age_text))
  present <- nzchar(age_text)
  if (any(present & (!is.finite(age) | age < 0 | age > 120 | age != floor(age))))
    stop("Age at admission must be a whole number from 0 to 120 or blank for unknown.", call. = FALSE)
  age[!present] <- NA_real_
  data$age_at_admission <- age
  data$age_band <- as.character(cut(age, breaks = c(-Inf, 64, 74, 84, Inf),
    labels = c("Under 65", "65-74", "75-84", "85 and over"), right = TRUE))
  data$age_band[is.na(age)] <- "Unknown"
  for (field in c("sex_recorded", "diagnostic_group")) data[[field]][!nzchar(data[[field]])] <- "Unknown"
  rownames(data) <- NULL
  data
}

join_demographics <- function(observations, demographics) {
  demographics <- validate_demographics(demographics)
  fields <- c("patient_id", "episode_id")
  if (!all(fields %in% names(observations))) stop("Normalized observations require patient and episode identifiers.", call. = FALSE)
  if (any(c("age_at_admission", "age_band", "sex_recorded", "diagnostic_group", "demographic_match") %in% names(observations)))
    stop("Join demographic fields only once.", call. = FALSE)
  obs_key <- advanced_key(observations, fields)
  demo_key <- advanced_key(demographics, fields)
  index <- match(obs_key, demo_key)
  result <- observations
  result$demographic_match <- !is.na(index)
  for (field in c("age_at_admission", "age_band", "sex_recorded", "diagnostic_group")) {
    result[[field]] <- demographics[[field]][index]
    if (field != "age_at_admission") result[[field]][is.na(index)] <- "Unknown"
  }
  # match() preserves every selected observation exactly once, in source order.
  stopifnot(nrow(result) == nrow(observations))
  audit <- data.frame(metric = c("selected_observations", "selected_patient_episodes", "matched_patient_episodes",
    "unmatched_patient_episodes", "unused_demographic_rows", "selected_patient_episodes_unknown_age"),
    count = c(nrow(result), length(unique(obs_key)), length(unique(obs_key[!is.na(index)])),
      length(unique(obs_key[is.na(index)])), sum(!demo_key %in% obs_key),
      length(unique(obs_key[is.na(result$age_at_admission)]))), stringsAsFactors = FALSE)
  list(data = result, audit = audit)
}

advanced_cohorts <- function(joined, config, policy) {
  current <- joined[joined$report_date >= config$start_date & joined$report_date <= config$end_date, , drop = FALSE]
  if (!nrow(current)) stop("No observations in the demographic reporting period.", call. = FALSE)
  rows <- list(); k <- 0L
  for (scope in c("All selected units", "Unit")) {
  for (dimension in c("age_band", "sex_recorded", "diagnostic_group")) {
    grouping <- if (scope == "Unit") c("unit", dimension) else dimension
    for (indices in sbm_group_indices(current, grouping)) {
      part <- current[indices, , drop = FALSE]
      for (metric in c("Sleep", "Any recorded behaviour")) {
        eligible <- if (metric == "Sleep") rep(TRUE, nrow(part)) else part$sleep_state == "awake"
        known <- if (metric == "Sleep") part$sleep_state %in% c("awake", "asleep") else eligible & part$behaviour %in% c("yes", "no")
        yes <- if (metric == "Sleep") part$sleep_state == "asleep" else eligible & part$behaviour == "yes"
        patients <- length(unique(part$patient_id[known]))
        # Repeat episodes cannot inflate the distinct-person privacy threshold.
        safe <- patients >= policy$MinGroupPatients
        k <- k + 1L
        rows[[k]] <- data.frame(scope = scope, unit = if (scope == "Unit") part$unit[1L] else "", dimension = dimension, group = part[[dimension]][1L], metric = metric,
          n_group_patients = length(unique(part$patient_id)), n_contributing_patients = patients,
          n_contributing_episodes = nrow(unique(part[known, c("patient_id", "episode_id"), drop = FALSE])),
          n_known = if (safe) sum(known) else NA_integer_, n_eligible = if (safe) sum(eligible) else NA_integer_,
          recorded_rate_pct = if (safe) sbm_percent(sum(yes), sum(known)) else NA_real_,
          recorded_completeness_pct = if (safe) sbm_percent(sum(known), sum(eligible)) else NA_real_,
          status = if (safe) "descriptive only" else "suppressed: too few contributing patients", stringsAsFactors = FALSE)
      }
    }
  }
  }
  result <- do.call(rbind, rows); rownames(result) <- NULL; result
}

advanced_backtest <- function(metric_daily, config, policy) {
  metrics <- c("Sleep", "Any recorded behaviour")
  keys <- c("patient_id", "episode_id", "unit", "report_date", "metric")
  if (!all(c(keys, "rate_pct", "n_known", "completeness_pct") %in% names(metric_daily)))
    stop("Backtesting requires shared daily metric counts and rates.", call. = FALSE)
  daily <- metric_daily[metric_daily$metric %in% metrics, , drop = FALSE]
  if (anyDuplicated(advanced_key(daily, keys))) stop("Duplicate daily target keys are not allowed.", call. = FALSE)
  if (!inherits(daily$report_date, "Date") || anyNA(daily$report_date)) stop("Daily dates must be known calendar dates.", call. = FALSE)
  if (any(is.finite(daily$rate_pct) & (daily$rate_pct < 0 | daily$rate_pct > 100))) stop("Daily rates must be percentages.", call. = FALSE)
  # The window depends on configured dates, never the last available observation.
  holdout_end <- as.Date(config$end_date)
  holdout_start <- holdout_end - policy$HoldoutDays + 1L
  if (holdout_start < as.Date(config$start_date)) stop("The report period must cover all 14 predeclared holdout dates.", call. = FALSE)
  eligible <- is.finite(daily$rate_pct) & is.finite(daily$n_known) & daily$n_known >= policy$MinKnownPerDay &
    is.finite(daily$completeness_pct) & daily$completeness_pct >= policy$MinCompletenessPct
  rows <- list(); exclusions <- list(); k <- 0L; q <- 0L
  for (indices in sbm_group_indices(daily, c("patient_id", "episode_id", "unit", "metric"))) {
    part <- daily[indices, , drop = FALSE]
    ok <- eligible[indices]
    targets <- which(part$report_date >= holdout_start & part$report_date <= holdout_end)
    for (j in targets) {
      target <- part$report_date[j]
      origin <- target - 1L
      last <- which(part$report_date == origin & ok)
      history <- which(part$report_date >= target - policy$TrailingCalendarDays & part$report_date <= origin & ok)
      status <- if (!ok[j]) "target below daily quality threshold"
        else if (length(last) != 1L) "no eligible immediately previous calendar day"
        else if (length(history) < policy$MinHistoryDays) "insufficient past days within seven calendar days"
        else "eligible"
      q <- q + 1L
      exclusions[[q]] <- data.frame(metric = part$metric[j], status = status, stringsAsFactors = FALSE)
      if (status != "eligible") next
      k <- k + 1L
      rows[[k]] <- cbind(part[j, c("patient_id", "episode_id", "unit", "metric"), drop = FALSE],
        data.frame(origin_date = origin, target_date = target, history_start_date = min(part$report_date[history]),
          history_end_date = max(part$report_date[history]), n_history_days = length(history), actual_pct = part$rate_pct[j],
          last_observed_day_pct = part$rate_pct[last], trailing_seven_day_mean_pct = mean(part$rate_pct[history]),
          target_n_known = part$n_known[j], stringsAsFactors = FALSE))
    }
  }
  paired <- if (length(rows)) do.call(rbind, rows) else data.frame(patient_id = character(), episode_id = character(), unit = character(),
    metric = character(), origin_date = as.Date(character()), target_date = as.Date(character()), history_start_date = as.Date(character()),
    history_end_date = as.Date(character()), n_history_days = integer(), actual_pct = numeric(), last_observed_day_pct = numeric(),
    trailing_seven_day_mean_pct = numeric(), target_n_known = integer(), stringsAsFactors = FALSE)
  rownames(paired) <- NULL
  summaries <- list(); k <- 0L
  for (metric in metrics) {
    part <- paired[paired$metric == metric, , drop = FALSE]
    n_patients <- length(unique(part$patient_id))
    safe <- n_patients >= policy$MinGroupPatients
    for (method in c("last_observed_day_pct", "trailing_seven_day_mean_pct")) {
      k <- k + 1L
      summaries[[k]] <- data.frame(metric = metric, method = method, n_targets = nrow(part), n_patients = n_patients,
        n_patient_episode_unit_groups = nrow(unique(part[c("patient_id", "episode_id", "unit")])),
        mae_percentage_points = if (safe) mean(abs(part$actual_pct - part[[method]])) else NA_real_,
        status = if (safe) "retrospective research only" else "suppressed: too few contributing patients", stringsAsFactors = FALSE)
    }
  }
  coverage <- if (length(exclusions)) aggregate(list(n_observed_targets = rep(1L, length(exclusions))),
    do.call(rbind, exclusions), sum) else data.frame(metric = character(), status = character(), n_observed_targets = integer())
  readiness <- data.frame(item = c("holdout_start", "holdout_end", "holdout_calendar_dates", "trailing_calendar_days", "min_history_days",
    "minimum_known_observations_per_day", "minimum_recorded_completeness_pct", "minimum_contributing_patients", "pending_next_day_forecasts"),
    value = c(as.character(holdout_start), as.character(holdout_end), policy$HoldoutDays, policy$TrailingCalendarDays,
      policy$MinHistoryDays, policy$MinKnownPerDay, policy$MinCompletenessPct, policy$MinGroupPatients, "disabled"), stringsAsFactors = FALSE)
  list(summary = do.call(rbind, summaries), coverage = coverage, readiness = readiness,
    paired_internal = paired, holdout_start = holdout_start, holdout_end = holdout_end)
}

make_synthetic_demographics <- function() {
  data.frame(patient_id = sprintf("Demo participant %02d", 1:8), episode_id = sprintf("DEMO-EP-%02d", 1:8),
    age_at_admission = c(65, 72, 76, 77, 78, 81, 84, NA),
    sex_recorded = rep(c("Female", "Male"), 4),
    diagnostic_group = rep(c("Fictional group A", "Fictional group B"), each = 4), stringsAsFactors = FALSE)
}
