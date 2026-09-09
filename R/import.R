# Explicit, local conversion of approved hospital exports into the shared contract.
# No name-derived keys, inferred date formats, DST guesses, or network access.

read_monitoring_import_config <- function(path) {
  if (!file.exists(path)) stop("Import configuration file does not exist.", call. = FALSE)
  raw <- read.dcf(path, all = TRUE)
  if (nrow(raw) != 1L) stop("Import configuration must contain exactly one DCF record.", call. = FALSE)
  values <- lapply(raw, function(column) {
    value <- column[[1L]]
    if (length(value) != 1L) stop("Import configuration fields must occur exactly once.", call. = FALSE)
    if (is.na(value)) "" else trimws(as.character(value))
  })
  value <- function(key) if (is.null(values[[key]])) "" else values[[key]]
  tokens <- function(key) {
    x <- trimws(strsplit(value(key), "|", fixed = TRUE)[[1L]])
    x[nzchar(x)]
  }
  mode <- value("TimestampMode")
  if (!mode %in% c("iso", "split")) stop("TimestampMode must be iso or split.", call. = FALSE)
  mapping_fields <- c(observation_id = "ObservationIdColumn", patient_id = "PatientIdColumn",
    episode_id = "EpisodeIdColumn", unit = "UnitColumn", sleep_state = "SleepStateColumn",
    behaviour = "BehaviourColumn", awake_calm = "AwakeCalmColumn", sleeping = "SleepingColumn")
  columns <- stats::setNames(vapply(mapping_fields, value, character(1L)), names(mapping_fields))
  if (any(!nzchar(columns[1:6]))) stop("Map all identifier, unit, sleep and behaviour columns explicitly.", call. = FALSE)
  if (mode == "iso") {
    if (!nzchar(value("TimestampColumn"))) stop("ISO import requires TimestampColumn.", call. = FALSE)
    unused <- c("DateColumn", "TimeColumn", "DateFormat", "TimeFormat", "UTCOffsetColumn", "UTCOffset")
    if (any(nzchar(vapply(unused, value, character(1L)))))
      stop("ISO import must leave separate date, time and offset settings blank.", call. = FALSE)
    timestamp_columns <- value("TimestampColumn")
  } else {
    if (nzchar(value("TimestampColumn"))) stop("Split import must leave TimestampColumn blank.", call. = FALSE)
    if (any(!nzchar(vapply(c("DateColumn", "TimeColumn"), value, character(1L)))))
      stop("Split import requires DateColumn and TimeColumn.", call. = FALSE)
    if (!value("DateFormat") %in% c("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y"))
      stop("DateFormat must be %Y-%m-%d, %d/%m/%Y or %m/%d/%Y; Excel serial dates are not inferred.", call. = FALSE)
    if (!value("TimeFormat") %in% c("%H:%M", "%H:%M:%S"))
      stop("TimeFormat must be %H:%M or %H:%M:%S; Excel serial times are not inferred.", call. = FALSE)
    if (nzchar(value("UTCOffsetColumn")) == nzchar(value("UTCOffset")))
      stop("Set exactly one of UTCOffsetColumn or UTCOffset for split import.", call. = FALSE)
    timestamp_columns <- c(value("DateColumn"), value("TimeColumn"), value("UTCOffsetColumn"))
  }
  behaviour_columns <- character()
  if (nzchar(value("BehaviourTypes"))) {
    entries <- strsplit(value("BehaviourTypes"), "|", fixed = TRUE)[[1L]]
    pairs <- lapply(entries, function(entry) trimws(strsplit(entry, "=", fixed = TRUE)[[1L]]))
    if (any(vapply(pairs, function(pair) length(pair) != 2L || any(!nzchar(pair)), logical(1L))))
      stop("BehaviourTypes requires Label=source column entries separated by |.", call. = FALSE)
    behaviour_columns <- stats::setNames(vapply(pairs, `[`, character(1L), 2L), vapply(pairs, `[`, character(1L), 1L))
  }
  extras <- tokens("ExtraColumns")
  selected <- c(columns, timestamp_columns, behaviour_columns, extras)
  selected <- unname(selected[nzchar(selected)])
  if (anyDuplicated(selected) || any(grepl("[[:cntrl:]]", selected)))
    stop("Map distinct source columns; mapped headings must contain no control characters.", call. = FALSE)
  target_behaviours <- sprintf("behaviour_type_%03d", seq_along(behaviour_columns))
  reserved <- c(names(columns), "observed_at", target_behaviours)
  if (length(intersect(extras, reserved))) stop("ExtraColumns must not collide with canonical column names.", call. = FALSE)

  import_fields <- c("TimestampMode", "DateColumn", "TimeColumn", "DateFormat", "TimeFormat", "UTCOffsetColumn", "UTCOffset", "ExtraColumns")
  report_values <- values[!names(values) %in% import_fields]
  for (key in names(mapping_fields)) report_values[[mapping_fields[[key]]]] <- if (nzchar(columns[[key]])) key else ""
  report_values$TimestampColumn <- "observed_at"
  report_values$BehaviourTypes <- if (length(behaviour_columns)) paste(paste(names(behaviour_columns), target_behaviours, sep = "="), collapse = "|") else ""
  config_file <- tempfile("sbm-import-config-", fileext = ".dcf")
  on.exit(unlink(config_file), add = TRUE)
  write.dcf(as.data.frame(report_values, stringsAsFactors = FALSE), config_file, width = 100000L)
  config <- read_monitoring_config(config_file)
  if (config$statistics_enabled) stop("Hospital imports require StatisticsEnabled: false.", call. = FALSE)
  list(mode = mode, columns = columns, timestamp_column = value("TimestampColumn"),
    date_column = value("DateColumn"), time_column = value("TimeColumn"),
    date_format = value("DateFormat"), time_format = value("TimeFormat"),
    offset_column = value("UTCOffsetColumn"), offset = value("UTCOffset"),
    behaviour_columns = behaviour_columns, target_behaviours = target_behaviours,
    extras = extras, selected_columns = selected, report_values = report_values, config = config)
}

sbm_import_split_timestamps <- function(dates, times, offsets, date_format, time_format, timezone) {
  # Parsing in UTC avoids implicit local-DST normalization before checking it.
  expected_date <- switch(date_format, "%Y-%m-%d" = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
    "%d/%m/%Y" = "^[0-9]{2}/[0-9]{2}/[0-9]{4}$", "%m/%d/%Y" = "^[0-9]{2}/[0-9]{2}/[0-9]{4}$")
  expected_time <- if (time_format == "%H:%M") "^[0-9]{2}:[0-9]{2}$" else "^[0-9]{2}:[0-9]{2}:[0-9]{2}$"
  bad <- which(is.na(dates) | is.na(times) | !grepl(expected_date, dates) | !grepl(expected_time, times))
  if (length(bad)) sbm_stop_rows("Date or time does not match the explicitly selected text format.", bad)
  combined <- paste(dates, times)
  fmt <- paste(date_format, time_format)
  parsed <- suppressWarnings(as.POSIXct(strptime(combined, fmt, tz = "UTC")))
  exact <- format(parsed, fmt, tz = "UTC", usetz = FALSE)
  bad <- which(is.na(parsed) | is.na(exact) | exact != combined)
  if (length(bad)) sbm_stop_rows("Invalid calendar date or clock time in the selected format.", bad)
  wall <- format(parsed, "%Y-%m-%dT%H:%M:%S", tz = "UTC", usetz = FALSE)
  bad <- which(is.na(offsets) | !grepl("^(Z|[+-][0-9]{2}:?[0-9]{2})$", offsets))
  if (length(bad)) sbm_stop_rows("UTC offsets must be explicit Z, +HHMM, -HHMM, +HH:MM or -HH:MM values.", bad)
  timestamp <- paste0(wall, offsets)
  instant <- sbm_parse_timestamps(timestamp, timezone)
  local <- format(instant, "%Y-%m-%dT%H:%M:%S", tz = timezone, usetz = FALSE)
  bad <- which(is.na(local) | local != wall)
  if (length(bad)) sbm_stop_rows("UTC offset does not match the local date/time in the configured timezone; verify DST and nonexistent times.", bad)
  timestamp
}

adapt_monitoring_export <- function(input, import) {
  if (!is.data.frame(input) || !nrow(input)) stop("Input must contain at least one observation.", call. = FALSE)
  if (anyDuplicated(names(input))) stop("Source column names must be unique; resolve duplicate headers.", call. = FALSE)
  if (!all(import$selected_columns %in% names(input)))
    stop("One or more explicitly mapped source headings are absent. Check the literal export headings.", call. = FALSE)
  text_column <- function(name) as.character(input[[name]])
  out <- stats::setNames(lapply(import$columns[nzchar(import$columns)], text_column), names(import$columns[nzchar(import$columns)]))
  ids <- out[c("observation_id", "patient_id", "episode_id", "unit")]
  bad <- which(Reduce(`|`, lapply(ids, function(x) !is.na(x) & x != trimws(x))))
  if (length(bad)) sbm_stop_rows("Identifiers and unit contain surrounding whitespace; reconcile the source without changing stable keys silently.", bad)
  if (import$mode == "iso") {
    out$observed_at <- text_column(import$timestamp_column)
    bad <- which(!is.na(out$observed_at) & out$observed_at != trimws(out$observed_at))
    if (length(bad)) sbm_stop_rows("ISO timestamps must have no surrounding whitespace.", bad)
    # Keep the source ISO offset: it may intentionally represent a UTC instant.
    sbm_parse_timestamps(out$observed_at, import$config$timezone)
  } else {
    offsets <- if (nzchar(import$offset_column)) text_column(import$offset_column) else rep(import$offset, nrow(input))
    out$observed_at <- sbm_import_split_timestamps(text_column(import$date_column), text_column(import$time_column),
      offsets, import$date_format, import$time_format, import$config$timezone)
  }
  if (length(import$behaviour_columns)) for (i in seq_along(import$behaviour_columns))
    out[[import$target_behaviours[[i]]]] <- text_column(import$behaviour_columns[[i]])
  for (name in import$extras) out[[name]] <- text_column(name)
  canonical <- as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
  # Validate every row before date filtering can affect the report. Unknown and
  # conflicting state codes remain source values; the shared engine flags them.
  normalized <- normalize_observations(canonical, import$config)
  list(data = canonical, normalized = normalized)
}

prepare_monitoring_import <- function(config_path, input_path, output) {
  if (length(output) != 1L || is.na(output) || !nzchar(output)) stop("Choose a new empty output directory.", call. = FALSE)
  if (file.exists(output) && !dir.exists(output)) stop("Output path is a file; the source cannot be overwritten.", call. = FALSE)
  if (dir.exists(output) && length(list.files(output, all.files = TRUE, no.. = TRUE)))
    stop("Output directory is not empty. Choose a new directory.", call. = FALSE)
  import <- read_monitoring_import_config(config_path)
  input <- read_monitoring_input(input_path)
  converted <- adapt_monitoring_export(input, import)
  if (!dir.exists(output) && !dir.create(output, recursive = TRUE, showWarnings = FALSE))
    stop("Cannot create the output directory.", call. = FALSE)
  # Check again after validation so earlier output is never deliberately replaced.
  if (length(list.files(output, all.files = TRUE, no.. = TRUE))) stop("Output directory is not empty.", call. = FALSE)
  csv_path <- file.path(output, "observations.csv")
  report_path <- file.path(output, "hospital.dcf")
  write.csv(converted$data, csv_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  write.dcf(as.data.frame(import$report_values, stringsAsFactors = FALSE), report_path, width = 100000L)
  receipt <- data.frame(Version = monitoring_version, Status = "validated",
    TimestampMode = import$mode, InputRows = nrow(input), OutputRows = nrow(converted$data),
    SelectedReportRows = nrow(converted$normalized$data),
    SelectedIssueCount = nrow(converted$normalized$issues),
    InputMD5 = unname(tools::md5sum(input_path)), ImportConfigMD5 = unname(tools::md5sum(config_path)),
    OutputMD5 = unname(tools::md5sum(csv_path)), stringsAsFactors = FALSE)
  write.dcf(receipt, file.path(output, "import-receipt.dcf"))
  invisible(list(output = normalizePath(output), input = normalizePath(csv_path),
    config = normalizePath(report_path), receipt = receipt))
}
