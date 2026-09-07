# Descriptive analytics for recorded point observations. Base R only.
# Unknown observations never become negative observations or measured duration.

sbm_stop_rows <- function(message, rows) {
  shown <- paste(utils::head(sort(unique(rows)), 12L), collapse = ", ")
  suffix <- if (length(unique(rows)) > 12L) ", ..." else ""
  stop(paste0(message, " Source rows: ", shown, suffix, "."), call. = FALSE)
}

sbm_text <- function(x) {
  x <- trimws(as.character(x))
  x[is.na(x)] <- ""
  x
}

sbm_codes <- function(x) unique(tolower(sbm_text(x)))

sbm_parse_timestamps <- function(x, timezone) {
  # Parse wall time independently of the supplied offset, then check roundtrip.
  # This rejects silent calendar rollover and does not guess a DST occurrence.
  x <- sbm_text(x)
  pattern <- paste0("^[0-9]{4}-[0-9]{2}-[0-9]{2}T", 
                    "[0-9]{2}:[0-9]{2}:[0-9]{2}",
                    "(Z|[+-][0-9]{2}:?[0-9]{2})$")
  bad <- which(!grepl(pattern, x))
  if (length(bad)) sbm_stop_rows(
    "Timestamps must include seconds and an explicit UTC offset (for example 2026-01-01T12:00:00+0000 or Z).", bad)
  wall <- substr(x, 1L, 19L)
  parsed <- suppressWarnings(as.POSIXct(strptime(wall, "%Y-%m-%dT%H:%M:%S", tz = "UTC")))
  roundtrip <- format(parsed, "%Y-%m-%dT%H:%M:%S", tz = "UTC", usetz = FALSE)
  bad <- which(is.na(parsed) | is.na(roundtrip) | roundtrip != wall |
                 as.integer(substr(wall, 18L, 19L)) > 59L)
  if (length(bad)) sbm_stop_rows("Invalid calendar date or clock time.", bad)
  offset <- gsub(":", "", substring(x, 20L), fixed = TRUE)
  zulu <- offset == "Z"
  hour <- minute <- rep(0L, length(x))
  hour[!zulu] <- as.integer(substr(offset[!zulu], 2L, 3L))
  minute[!zulu] <- as.integer(substr(offset[!zulu], 4L, 5L))
  bad <- which(hour > 23L | minute > 59L)
  if (length(bad)) sbm_stop_rows("Invalid UTC offset.", bad)
  sign <- ifelse(substr(offset, 1L, 1L) == "-", -1L, 1L)
  utc <- as.numeric(parsed) - sign * (hour * 3600L + minute * 60L)
  as.POSIXct(utc, origin = "1970-01-01", tz = timezone)
}

sbm_check_bands <- function(bands) {
  if (!is.data.frame(bands) || !all(c("name", "start", "end") %in% names(bands)) ||
      !nrow(bands)) stop("Time bands must provide name, start, and end.", call. = FALSE)
  bands$name <- sbm_text(bands$name)
  if (any(!nzchar(bands$name)) || anyDuplicated(bands$name) || "Total" %in% bands$name ||
      any(grepl("[[:cntrl:]]", bands$name)))
    stop("Time band names must be unique, nonblank, and must not use Total.", call. = FALSE)
  if (!is.numeric(bands$start) || !is.numeric(bands$end) ||
      any(!is.finite(bands$start)) || any(!is.finite(bands$end)) ||
      any(bands$start < 0 | bands$start >= 1440 | bands$end < 0 | bands$end > 1440) ||
      any(bands$start != floor(bands$start) | bands$end != floor(bands$end)) ||
      any(bands$start == bands$end))
    stop("Time bands require integer minute boundaries, distinct start/end, start 0..1439 and end 0..1440.", call. = FALSE)
  membership <- vapply(seq_len(nrow(bands)), function(i) {
    m <- 0:1439
    if (bands$start[i] < bands$end[i]) m >= bands$start[i] & m < bands$end[i]
    else m >= bands$start[i] | m < bands$end[i]
  }, logical(1440L))
  if (any(rowSums(membership) != 1L))
    stop("Time bands must cover every clock minute exactly once without gaps or overlaps.", call. = FALSE)
  bands
}

sbm_date_window <- function(config) {
  date_value <- function(x, name, optional = FALSE) {
    if (is.null(x) || !length(x) || (length(x) == 1L && is.na(x))) {
      if (optional) return(as.Date(NA))
      stop(paste(name, "is required."), call. = FALSE)
    }
    if (length(x) != 1L) stop(paste(name, "must be one date."), call. = FALSE)
    d <- suppressWarnings(as.Date(x))
    if (is.na(d)) stop(paste(name, "must be a valid date."), call. = FALSE)
    d
  }
  start <- date_value(config$start_date, "start_date")
  end <- date_value(config$end_date, "end_date")
  if (end < start) stop("end_date must be on or after start_date.", call. = FALSE)
  bs <- date_value(config$baseline_start, "baseline_start", TRUE)
  be <- date_value(config$baseline_end, "baseline_end", TRUE)
  if (xor(is.na(bs), is.na(be))) stop("Provide both baseline dates or neither.", call. = FALSE)
  enabled <- !is.na(bs)
  if (enabled && (be < bs || be >= start))
    stop("The baseline must end before the report starts, with baseline_end on or after baseline_start.", call. = FALSE)
  list(start = start, end = end, baseline_start = bs, baseline_end = be, baseline_enabled = enabled)
}

normalize_observations <- function(data, config) {
  if (!is.data.frame(data) || !nrow(data)) stop("Input must contain at least one observation.", call. = FALSE)
  if (anyDuplicated(names(data))) stop("Source column names must be unique; resolve duplicate headers before reporting.", call. = FALSE)
  required <- c("observation_id", "patient_id", "episode_id", "unit", "observed_at", "sleep_state", "behaviour")
  columns <- config$columns
  if (is.null(names(columns)) || !all(required %in% names(columns)))
    stop("Column mapping must include all seven required canonical fields.", call. = FALSE)
  column_values <- unlist(columns, use.names = TRUE)
  if (any(!nzchar(column_values[required])) || !all(column_values[required] %in% names(data)))
    stop("One or more required mapped columns are absent from the input.", call. = FALSE)
  if (anyDuplicated(column_values[nzchar(column_values)]))
    stop("Each canonical field must map to a distinct source column.", call. = FALSE)
  timezone <- config$timezone
  if (is.null(timezone) || length(timezone) != 1L || !timezone %in% c("UTC", "GMT", OlsonNames()))
    stop("timezone must name a recognised IANA time zone.", call. = FALSE)
  bands <- sbm_check_bands(config$bands)
  window <- sbm_date_window(config)
  day_start <- if (is.null(config$reporting_day_start)) 0L else config$reporting_day_start
  if (length(day_start) != 1L || !is.numeric(day_start) || is.na(day_start) ||
      day_start != floor(day_start) || day_start < 0 || day_start >= 1440)
    stop("reporting_day_start must be an integer clock minute from 0 to 1439.", call. = FALSE)
  get_column <- function(name, optional = FALSE) {
    mapped <- column_values[name]
    if (!length(mapped) || is.na(mapped) || !nzchar(mapped)) return(rep("", nrow(data)))
    if (!mapped %in% names(data)) {
      if (optional) stop("A configured optional fallback column is absent from the input.", call. = FALSE)
      stop("A required mapped column is absent from the input.", call. = FALSE)
    }
    sbm_text(data[[mapped]])
  }
  ids <- as.data.frame(setNames(lapply(required[1:4], get_column), required[1:4]), stringsAsFactors = FALSE)
  bad <- which(Reduce(`|`, lapply(ids, function(x) !nzchar(x) | grepl("[[:cntrl:]]", x))))
  if (length(bad)) sbm_stop_rows("Identifiers and unit must be nonblank and contain no control characters.", bad)
  observed_at <- sbm_parse_timestamps(get_column("observed_at"), timezone)
  dup_id <- duplicated(ids$observation_id) | duplicated(ids$observation_id, fromLast = TRUE)
  if (any(dup_id)) sbm_stop_rows("Duplicate observation identifiers; reconcile repeated or conflicting records before reporting.", which(dup_id))
  duplicate_key <- data.frame(patient_id = ids$patient_id, episode_id = ids$episode_id, observed_at = as.numeric(observed_at))
  dup_key <- duplicated(duplicate_key) | duplicated(duplicate_key, fromLast = TRUE)
  if (any(dup_key)) sbm_stop_rows("Duplicate patient, episode, and observation time; reconcile records before reporting.", which(dup_key))
  codes <- lapply(config$codes, sbm_codes)
  needed_codes <- c("awake", "asleep", "behaviour_yes", "behaviour_no")
  if (!all(needed_codes %in% names(codes)) || any(vapply(codes[needed_codes], function(x) !length(x) || any(!nzchar(x)), logical(1))))
    stop("Nonblank codes are required for awake, asleep, behaviour_yes, and behaviour_no.", call. = FALSE)
  if (length(intersect(codes$awake, codes$asleep)) || length(intersect(codes$behaviour_yes, codes$behaviour_no)))
    stop("Awake/asleep and behaviour yes/no code sets must not overlap.", call. = FALSE)
  sleep_raw <- tolower(get_column("sleep_state"))
  behaviour_raw <- tolower(get_column("behaviour"))
  calm_raw <- tolower(get_column("awake_calm", TRUE))
  sleeping_raw <- tolower(get_column("sleeping", TRUE))
  calm <- nzchar(calm_raw) & calm_raw %in% codes$awake_calm
  sleeping <- nzchar(sleeping_raw) & sleeping_raw %in% codes$sleeping
  bad_calm <- nzchar(calm_raw) & !calm
  bad_sleeping <- nzchar(sleeping_raw) & !sleeping
  sleep <- rep("unknown", nrow(data))
  sleep[sleep_raw %in% codes$awake] <- "awake"
  sleep[sleep_raw %in% codes$asleep] <- "asleep"
  behaviour <- rep("unknown", nrow(data))
  behaviour[behaviour_raw %in% codes$behaviour_yes] <- "yes"
  behaviour[behaviour_raw %in% codes$behaviour_no] <- "no"
  issues <- data.frame(row = integer(), code = character(), message = character(), stringsAsFactors = FALSE)
  add_issue <- function(mask, code, message) {
    rows <- which(mask)
    if (length(rows)) issues <<- rbind(issues, data.frame(row = rows, code = code, message = message, stringsAsFactors = FALSE))
  }
  add_issue(bad_calm, "unmapped_awake_calm", "Unmapped awake-calm fallback flag; fallback inference is disabled for this row.")
  add_issue(bad_sleeping, "unmapped_sleeping", "Unmapped sleeping fallback flag; fallback inference is disabled for this row.")
  fallback_ok <- !bad_calm & !bad_sleeping & !(calm & sleeping)
  sleep[!nzchar(sleep_raw) & fallback_ok & calm] <- "awake"
  sleep[!nzchar(sleep_raw) & fallback_ok & sleeping] <- "asleep"
  sleep_conflict <- (calm & sleeping) | (sleep_raw %in% codes$awake & sleeping) | (sleep_raw %in% codes$asleep & calm)
  sleep[sleep_conflict] <- "unknown"
  add_issue(sleep_conflict, "conflicting_sleep", "Contradictory sleep evidence; sleep state is unknown.")
  add_issue(sleep == "unknown" & !sleep_conflict & !nzchar(sleep_raw), "missing_sleep", "Sleep state is missing without a usable fallback.")
  add_issue(sleep == "unknown" & !sleep_conflict & nzchar(sleep_raw), "unmapped_sleep", "Sleep code is unmapped; sleep state is unknown.")
  add_issue(behaviour == "unknown" & !nzchar(behaviour_raw), "missing_behaviour", "Behaviour is missing; only explicit behaviour codes establish yes or no.")
  add_issue(behaviour == "unknown" & nzchar(behaviour_raw), "unmapped_behaviour", "Behaviour code is unmapped; behaviour is unknown.")
  add_issue(behaviour == "yes" & sleep != "awake", "behaviour_excluded", "Recorded behaviour is outside the confirmed-awake denominator.")
  local_date <- as.Date(format(observed_at, "%Y-%m-%d", tz = timezone))
  hour <- as.integer(format(observed_at, "%H", tz = timezone))
  clock_minute <- hour * 60L + as.integer(format(observed_at, "%M", tz = timezone))
  # Calendar subtraction, not an elapsed-seconds shift: this holds across DST.
  report_date <- local_date - as.integer(clock_minute < day_start)
  band <- rep(NA_character_, nrow(data))
  for (i in seq_len(nrow(bands))) {
    inside <- if (bands$start[i] < bands$end[i]) clock_minute >= bands$start[i] & clock_minute < bands$end[i]
    else clock_minute >= bands$start[i] | clock_minute < bands$end[i]
    band[inside] <- bands$name[i]
  }
  canonical <- cbind(ids, data.frame(observed_at = observed_at, report_date = report_date,
    band = band, hour = hour, sleep_state = sleep, behaviour = behaviour,
    source_row = seq_len(nrow(data)), stringsAsFactors = FALSE))
  current <- report_date >= window$start & report_date <= window$end
  baseline <- rep(FALSE, nrow(data))
  if (window$baseline_enabled) baseline <- report_date >= window$baseline_start & report_date <= window$baseline_end
  selection <- rep(TRUE, nrow(data))
  if (length(config$units)) selection <- selection & ids$unit %in% config$units
  if (length(config$patients)) selection <- selection & ids$patient_id %in% config$patients
  if (!any(current & selection)) stop("No observations match the report dates, units, and patients.", call. = FALSE)
  canonical <- canonical[(current | baseline) & selection, , drop = FALSE]
  issues <- issues[issues$row %in% canonical$source_row, , drop = FALSE]
  issues <- issues[order(issues$row, issues$code), , drop = FALSE]
  rownames(canonical) <- rownames(issues) <- NULL
  list(data = canonical, issues = issues)
}

sbm_percent <- function(numerator, denominator) {
  ifelse(denominator > 0, 100 * numerator / denominator, NA_real_)
}

sbm_metrics <- function(data, band_hours = NA_real_, estimate_hours = FALSE) {
  asleep <- sum(data$sleep_state == "asleep")
  awake <- sum(data$sleep_state == "awake")
  known_behaviour <- sum(data$sleep_state == "awake" & data$behaviour %in% c("yes", "no"))
  yes_behaviour <- sum(data$sleep_state == "awake" & data$behaviour == "yes")
  result <- data.frame(n_observations = nrow(data), n_sleep_known = asleep + awake,
    n_asleep = asleep, n_awake = awake, sleep_pct = sbm_percent(asleep, asleep + awake),
    sleep_known_pct = sbm_percent(asleep + awake, nrow(data)),
    n_behaviour_known_awake = known_behaviour, n_behaviour_yes_awake = yes_behaviour,
    behaviour_pct = sbm_percent(yes_behaviour, known_behaviour),
    behaviour_known_awake_pct = sbm_percent(known_behaviour, awake))
  if (estimate_hours) result$standardized_sleep_hours <- result$sleep_pct / 100 * band_hours
  result
}

sbm_group_indices <- function(data, keys) {
  if (!nrow(data)) return(list())
  key <- do.call(paste, c(lapply(data[keys], as.character), sep = "\034"))
  split(seq_len(nrow(data)), key, drop = TRUE)
}

sbm_summarize_bands <- function(data, keys, config) {
  band_names <- c(as.character(config$bands$name), "Total")
  hours <- (config$bands$end - config$bands$start) %% 1440 / 60
  hours[config$bands$start == 0 & config$bands$end == 1440] <- 24
  names(hours) <- config$bands$name
  hours <- c(hours, Total = 24)
  output <- list()
  j <- 0L
  for (indices in sbm_group_indices(data, keys)) {
    group <- data[indices, , drop = FALSE]
    for (band in band_names) {
      selected <- if (band == "Total") group else group[group$band == band, , drop = FALSE]
      j <- j + 1L
      output[[j]] <- cbind(group[1L, keys, drop = FALSE], data.frame(band = band, stringsAsFactors = FALSE),
        sbm_metrics(selected, unname(hours[band]), isTRUE(config$estimate_hours)))
    }
  }
  if (!length(output)) {
    result <- cbind(data[FALSE, keys, drop = FALSE], data.frame(band = character()), sbm_metrics(data[FALSE, , drop = FALSE], 0, isTRUE(config$estimate_hours))[FALSE, , drop = FALSE])
  } else result <- do.call(rbind, output)
  rownames(result) <- NULL
  result
}

sbm_mean_known <- function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)

sbm_baseline <- function(patient, baseline_data, config, window) {
  keys <- c("patient_id", "episode_id", "unit", "band")
  previous <- sbm_summarize_bands(baseline_data, keys[1:3], config)
  metric_names <- setdiff(names(patient), keys)
  current <- patient
  names(current)[match(metric_names, names(current))] <- paste0("report_", metric_names)
  names(previous)[match(metric_names, names(previous))] <- paste0("baseline_", metric_names)
  previous$baseline_match <- rep(TRUE, nrow(previous))
  result <- merge(current, previous, by = keys, all.x = TRUE, sort = FALSE)
  matched <- !is.na(result$baseline_match)
  result$baseline_match <- NULL
  minimum <- if (is.null(config$min_baseline_observations)) 10L else config$min_baseline_observations
  completeness <- if (is.null(config$min_completeness_pct)) 80 else config$min_completeness_pct
  if (length(minimum) != 1L || !is.numeric(minimum) || !is.finite(minimum) || minimum < 1 || minimum != floor(minimum))
    stop("min_baseline_observations must be a positive integer.", call. = FALSE)
  if (length(completeness) != 1L || !is.numeric(completeness) || !is.finite(completeness) || completeness < 0 || completeness > 100)
    stop("min_completeness_pct must be between 0 and 100.", call. = FALSE)
  status <- function(known_name, completeness_name) {
    output <- rep("eligible", nrow(result))
    for (i in seq_len(nrow(result))) {
      output[i] <- if (!window$baseline_enabled) "baseline disabled"
      else if (!matched[i]) "no matching baseline admission"
      else if (is.na(result[[paste0("baseline_", known_name)]][i]) || result[[paste0("baseline_", known_name)]][i] < minimum) "insufficient baseline known observations"
      else if (is.na(result[[paste0("report_", known_name)]][i]) || result[[paste0("report_", known_name)]][i] < minimum) "insufficient report known observations"
      else if (is.na(result[[paste0("baseline_", completeness_name)]][i]) || result[[paste0("baseline_", completeness_name)]][i] < completeness) "baseline recorded completeness below minimum"
      else if (is.na(result[[paste0("report_", completeness_name)]][i]) || result[[paste0("report_", completeness_name)]][i] < completeness) "report recorded completeness below minimum"
      else "eligible"
    }
    output
  }
  result$sleep_status <- status("n_sleep_known", "sleep_known_pct")
  result$behaviour_status <- status("n_behaviour_known_awake", "behaviour_known_awake_pct")
  result$sleep_eligible <- result$sleep_status == "eligible"
  result$behaviour_eligible <- result$behaviour_status == "eligible"
  result$sleep_change_pp <- ifelse(result$sleep_eligible, result$report_sleep_pct - result$baseline_sleep_pct, NA_real_)
  result$behaviour_change_pp <- ifelse(result$behaviour_eligible, result$report_behaviour_pct - result$baseline_behaviour_pct, NA_real_)
  result
}

summarize_observations <- function(data, config) {
  if (is.list(data) && !is.data.frame(data) && !is.null(data$data)) data <- data$data
  if (!is.data.frame(data) || !all(c("patient_id", "episode_id", "unit", "report_date", "band", "hour", "sleep_state", "behaviour") %in% names(data)))
    stop("summarize_observations requires normalized observations.", call. = FALSE)
  window <- sbm_date_window(config)
  config$bands <- sbm_check_bands(config$bands)
  selection <- rep(TRUE, nrow(data))
  if (length(config$units)) selection <- selection & data$unit %in% config$units
  if (length(config$patients)) selection <- selection & data$patient_id %in% config$patients
  current <- data[selection & data$report_date >= window$start & data$report_date <= window$end, , drop = FALSE]
  if (!nrow(current)) stop("No observations match the reporting scope.", call. = FALSE)
  baseline_data <- data[FALSE, , drop = FALSE]
  if (window$baseline_enabled) baseline_data <- data[selection & data$report_date >= window$baseline_start & data$report_date <= window$baseline_end, , drop = FALSE]
  keys <- c("patient_id", "episode_id", "unit")
  patient <- sbm_summarize_bands(current, keys, config)
  daily <- sbm_summarize_bands(current, c(keys, "report_date"), config)
  hourly_rows <- lapply(sbm_group_indices(current, c(keys, "hour")), function(indices) {
    group <- current[indices, , drop = FALSE]
    cbind(group[1L, c(keys, "hour"), drop = FALSE], sbm_metrics(group, 1, isTRUE(config$estimate_hours)))
  })
  hourly <- do.call(rbind, hourly_rows)
  rownames(hourly) <- NULL
  pooled <- sbm_summarize_bands(current, "unit", config)
  pooled$aggregation <- "pooled_observations"
  pooled$n_admissions <- pooled$n_sleep_admissions <- pooled$n_behaviour_admissions <- 0L
  unit_mean <- pooled
  unit_mean$aggregation <- "equal_admission"
  count_names <- c("n_observations", "n_sleep_known", "n_asleep", "n_awake", "n_behaviour_known_awake", "n_behaviour_yes_awake")
  mean_names <- c("sleep_pct", "sleep_known_pct", "behaviour_pct", "behaviour_known_awake_pct")
  if (isTRUE(config$estimate_hours)) mean_names <- c(mean_names, "standardized_sleep_hours")
  for (i in seq_len(nrow(pooled))) {
    patients <- patient[patient$unit == pooled$unit[i] & patient$band == pooled$band[i], , drop = FALSE]
    pooled$n_admissions[i] <- sum(patients$n_observations > 0)
    pooled$n_sleep_admissions[i] <- sum(patients$n_sleep_known > 0)
    pooled$n_behaviour_admissions[i] <- sum(patients$n_behaviour_known_awake > 0)
    for (metric in mean_names) unit_mean[[metric]][i] <- sbm_mean_known(patients[[metric]])
    for (metric in count_names) unit_mean[[metric]][i] <- NA_real_
  }
  unit_mean[c("n_admissions", "n_sleep_admissions", "n_behaviour_admissions")] <- pooled[c("n_admissions", "n_sleep_admissions", "n_behaviour_admissions")]
  unit <- rbind(pooled, unit_mean)
  unit <- unit[c("unit", "band", "aggregation", setdiff(names(unit), c("unit", "band", "aggregation")))]
  rownames(unit) <- NULL
  baseline <- sbm_baseline(patient, baseline_data, config, window)
  overall <- sbm_metrics(current)
  quality <- data.frame(
    metric = c("report_observations", "baseline_observations", "patient_episode_unit_groups",
      "unknown_sleep_observations", "unknown_behaviour_among_awake_observations",
      "behaviour_yes_excluded_from_awake_denominator", "recorded_sleep_state_completeness_pct",
      "recorded_awake_behaviour_completeness_pct"),
    value = c(nrow(current), nrow(baseline_data), nrow(unique(current[keys])),
      sum(current$sleep_state == "unknown"), sum(current$sleep_state == "awake" & current$behaviour == "unknown"),
      sum(current$sleep_state != "awake" & current$behaviour == "yes"), overall$sleep_known_pct,
      overall$behaviour_known_awake_pct), stringsAsFactors = FALSE)
  list(patient = patient, unit = unit, daily = daily, hourly = hourly, baseline = baseline, quality = quality)
}
