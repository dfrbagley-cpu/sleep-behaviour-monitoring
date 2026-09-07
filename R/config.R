# Plain-text configuration, with no executable settings or embedded credentials.
monitoring_version <- "0.1.0"

read_monitoring_config <- function(path) {
  if (!file.exists(path)) stop("Configuration file does not exist.", call. = FALSE)
  raw <- read.dcf(path, all = TRUE)
  if (nrow(raw) != 1L) stop("Configuration must contain exactly one DCF record.", call. = FALSE)
  values <- as.list(raw[1, , drop = FALSE])
  required <- c("Title", "Timezone", "StartDate", "EndDate", "TimeBands",
                "ObservationIdColumn", "PatientIdColumn", "EpisodeIdColumn", "UnitColumn",
                "TimestampColumn", "SleepStateColumn", "BehaviourColumn")
  optional <- c("BaselineStart", "BaselineEnd", "ReportingDayStart", "Units", "Patients",
                "AwakeCalmColumn", "SleepingColumn", "AwakeCodes", "AsleepCodes",
                "BehaviourYesCodes", "BehaviourNoCodes", "AwakeCalmCodes", "SleepingCodes",
                "EstimateHours", "MinBaselineObservations", "MinCompletenessPct")
  if (any(!names(values) %in% c(required, optional))) stop("Unknown configuration field; check the example file.", call. = FALSE)
  if (any(!required %in% names(values))) stop("Missing required configuration fields: ", paste(setdiff(required, names(values)), collapse = ", "), call. = FALSE)
  val <- function(key, default = "") if (is.null(values[[key]]) || is.na(values[[key]])) default else trimws(values[[key]])
  tokens <- function(key, default = "") {
    x <- trimws(strsplit(val(key, default), "|", fixed = TRUE)[[1]])
    unique(x[nzchar(x)])
  }
  date <- function(key, allow_empty = FALSE) {
    x <- val(key)
    if (!nzchar(x) && allow_empty) return(as.Date(NA))
    d <- suppressWarnings(as.Date(x, format = "%Y-%m-%d"))
    if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", x) || is.na(d) || format(d, "%Y-%m-%d") != x)
      stop(key, " must be an ISO date (YYYY-MM-DD).", call. = FALSE)
    d
  }
  clock <- function(x, allow_end = FALSE) {
    if (allow_end && identical(x, "24:00")) return(1440L)
    if (!grepl("^([01][0-9]|2[0-3]):[0-5][0-9]$", x)) stop("Time settings require HH:MM.", call. = FALSE)
    as.integer(substr(x, 1, 2)) * 60L + as.integer(substr(x, 4, 5))
  }
  parts <- strsplit(val("TimeBands"), "|", fixed = TRUE)[[1]]
  bands <- do.call(rbind, lapply(parts, function(x) {
    pair <- strsplit(trimws(x), "=", fixed = TRUE)[[1]]
    if (length(pair) != 2L || !nzchar(trimws(pair[1]))) stop("TimeBands must use Name=HH:MM-HH:MM separated by |.", call. = FALSE)
    bounds <- strsplit(pair[2], "-", fixed = TRUE)[[1]]
    if (length(bounds) != 2L) stop("Each time band needs two boundaries.", call. = FALSE)
    data.frame(name = trimws(pair[1]), start = clock(trimws(bounds[1])), end = clock(trimws(bounds[2]), TRUE), stringsAsFactors = FALSE)
  }))
  if (anyDuplicated(bands$name) || any(tolower(bands$name) == "total") || nrow(bands) > 12L)
    stop("Use up to 12 unique band names; Total is reserved.", call. = FALSE)
  cover <- integer(1440)
  for (i in seq_len(nrow(bands))) {
    s <- bands$start[i]; e <- bands$end[i]; m <- 0:1439
    if (s == e) stop("A time band cannot have equal boundaries.", call. = FALSE)
    cover <- cover + if (s < e) (m >= s & m < e) else (m >= s | m < e)
  }
  if (any(cover != 1L)) stop("Time bands must cover the clock once, with no gaps or overlaps.", call. = FALSE)
  integer_setting <- function(key, default, lo, hi) {
    x <- suppressWarnings(as.numeric(val(key, as.character(default))))
    if (length(x) != 1 || !is.finite(x) || x != floor(x) || x < lo || x > hi) stop("Invalid ", key, ".", call. = FALSE)
    as.integer(x)
  }
  estimate <- tolower(val("EstimateHours", "false"))
  if (!estimate %in% c("true", "false")) stop("EstimateHours must be true or false.", call. = FALSE)
  config <- list(
    version = monitoring_version, title = val("Title"), timezone = val("Timezone"), synthetic = FALSE,
    start_date = date("StartDate"), end_date = date("EndDate"),
    baseline_start = date("BaselineStart", TRUE), baseline_end = date("BaselineEnd", TRUE),
    reporting_day_start = clock(val("ReportingDayStart", "00:00")), bands = bands,
    units = tokens("Units"), patients = tokens("Patients"), estimate_hours = estimate == "true",
    min_baseline_observations = integer_setting("MinBaselineObservations", 10L, 1L, 1000000L),
    min_completeness_pct = integer_setting("MinCompletenessPct", 80L, 0L, 100L),
    columns = c(observation_id = val("ObservationIdColumn"), patient_id = val("PatientIdColumn"),
                episode_id = val("EpisodeIdColumn"), unit = val("UnitColumn"), observed_at = val("TimestampColumn"),
                sleep_state = val("SleepStateColumn"), behaviour = val("BehaviourColumn"),
                awake_calm = val("AwakeCalmColumn"), sleeping = val("SleepingColumn")),
    codes = list(awake = tokens("AwakeCodes", "Awake"), asleep = tokens("AsleepCodes", "Asleep"),
                 behaviour_yes = tokens("BehaviourYesCodes", "YES"), behaviour_no = tokens("BehaviourNoCodes", "NO"),
                 awake_calm = tokens("AwakeCalmCodes", "Awake/Calm"), sleeping = tokens("SleepingCodes", "Sleeping")))
  if (!nzchar(config$title) || !config$timezone %in% c("UTC", OlsonNames())) stop("Provide a title and valid IANA timezone.", call. = FALSE)
  if (config$start_date > config$end_date) stop("StartDate must not follow EndDate.", call. = FALSE)
  if (xor(is.na(config$baseline_start), is.na(config$baseline_end))) stop("Provide both baseline dates or neither.", call. = FALSE)
  if (!is.na(config$baseline_start) && (config$baseline_start > config$baseline_end || config$baseline_end >= config$start_date)) stop("Baseline must be an earlier, nonoverlapping period.", call. = FALSE)
  required_cols <- config$columns[seq_len(7)]
  if (any(!nzchar(required_cols)) || anyDuplicated(config$columns[nzchar(config$columns)])) stop("Mapped columns must be nonempty and distinct.", call. = FALSE)
  for (pair in list(c("awake", "asleep"), c("behaviour_yes", "behaviour_no"))) {
    if (!length(config$codes[[pair[1]]]) || !length(config$codes[[pair[2]]]) ||
        length(intersect(tolower(config$codes[[pair[1]]]), tolower(config$codes[[pair[2]]])))) stop("State code sets must be nonempty and disjoint.", call. = FALSE)
  }
  config
}

read_monitoring_input <- function(path) {
  if (!file.exists(path)) stop("Input file does not exist.", call. = FALSE)
  extension <- tolower(tools::file_ext(path))
  if (extension == "csv") return(read.csv(path, colClasses = "character", check.names = FALSE, na.strings = c(""), strip.white = TRUE))
  if (extension == "xlsx") {
    if (!requireNamespace("readxl", quietly = TRUE)) stop("XLSX input requires readxl. Run Rscript --vanilla scripts/install_optional.R once.", call. = FALSE)
    return(as.data.frame(readxl::read_excel(path, col_types = "text", .name_repair = "minimal"), stringsAsFactors = FALSE))
  }
  stop("Input must be CSV or an unencrypted XLSX file. Convert encrypted exports locally using your approved workflow.", call. = FALSE)
}
