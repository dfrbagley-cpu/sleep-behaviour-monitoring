# Retain selected source rows verbatim as text plus clearly separate derived fields.
# Worksheet export escapes formula-like text; this function does not mutate values.
prepare_monitoring_raw_data <- function(input, data, config) {
  if (!is.data.frame(input) || !is.data.frame(data) || !"source_row" %in% names(data)) stop("Raw-data export requires validated source rows.")
  rows <- data$source_row
  if (!is.numeric(rows) || any(!is.finite(rows)) || any(rows != floor(rows)) ||
      any(rows < 1L | rows > nrow(input)) || anyDuplicated(rows)) stop("Invalid raw-data source-row mapping.")
  raw <- input[rows, , drop = FALSE]
  raw[] <- lapply(raw, as.character)
  derived <- data
  derived$observed_at <- format(data$observed_at, "%Y-%m-%dT%H:%M:%S%z", tz = config$timezone)
  derived$report_date <- as.character(data$report_date)
  derived$period <- ifelse(data$report_date >= config$start_date & data$report_date <= config$end_date, "Report", "Baseline")
  prefix <- "analysis_"
  while (any(paste0(prefix, names(derived)) %in% names(raw))) prefix <- paste0("_", prefix)
  names(derived) <- paste0(prefix, names(derived))
  result <- cbind(raw, derived)
  rownames(result) <- NULL
  attr(result, "derived_prefix") <- prefix
  attr(result, "source_columns") <- names(raw)
  attr(result, "derived_columns") <- names(derived)
  result
}
