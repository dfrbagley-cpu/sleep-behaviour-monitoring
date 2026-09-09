#!/usr/bin/env Rscript
# Hospital adapter regressions: synthetic rows only, no hospital exports required.
args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[startsWith(args, "--file=")])
root <- if (length(script)) dirname(dirname(normalizePath(script[1L]))) else normalizePath(".")
for (file in c("config.R", "analytics.R", "import.R")) source(file.path(root, "R", file))
checks <- list()
test <- function(name, expr) {
  problem <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  checks[[length(checks) + 1L]] <<- list(name = name, problem = problem)
  cat(if (is.null(problem)) "PASS" else "FAIL", "-", name, "\n")
  if (!is.null(problem)) cat("  ", problem, "\n", sep = "")
}
reject <- function(expr, pattern) {
  message <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  stopifnot(nzchar(message), grepl(pattern, message, ignore.case = TRUE))
  invisible(message)
}
with_import <- function(changes = list(), callback) {
  values <- as.list(read.dcf(file.path(root, "config", "import.example.dcf"))[1L, ])
  defaults <- list(StartDate = "2026-01-01", EndDate = "2026-12-31", BaselineStart = "", BaselineEnd = "",
    ObservationIdColumn = "Observation key", PatientIdColumn = "Person key", EpisodeIdColumn = "Admission key",
    UnitColumn = "Ward", TimestampColumn = "Recorded at", SleepStateColumn = "Sleep", BehaviourColumn = "Behaviour",
    AwakeCalmColumn = "", SleepingColumn = "")
  for (key in names(defaults)) values[[key]] <- defaults[[key]]
  for (key in names(changes)) values[[key]] <- changes[[key]]
  directory <- tempfile("sbm-import-test-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  path <- file.path(directory, "import.dcf")
  write.dcf(as.data.frame(values, stringsAsFactors = FALSE), path, width = 100000L)
  callback(path, directory)
}
import_fixture <- function() {
  data.frame("Observation key" = c("000001", "000002"), "Person key" = c("0007", "0007"),
    "Admission key" = c("0012", "0012"), Ward = c("Synthetic ward", "Synthetic ward"),
    "Recorded at" = c("2026-08-01T12:00:00Z", "2026-08-01T13:00:00Z"),
    Sleep = c("Awake", "Asleep"), Behaviour = c("", "NO"),
    "Patient name" = c("DO NOT COPY SYNTHETIC NAME", "DO NOT COPY SYNTHETIC NAME"),
    source_note = c("=1+1", "synthetic note"), check.names = FALSE, stringsAsFactors = FALSE)
}
split_settings <- function(...) {
  settings <- list(TimestampMode = "split", TimestampColumn = "", DateColumn = "Date", TimeColumn = "Time",
    DateFormat = "%Y-%m-%d", TimeFormat = "%H:%M:%S", UTCOffsetColumn = "Offset")
  changes <- list(...)
  for (name in names(changes)) settings[[name]] <- changes[[name]]
  settings
}
split_fixture <- function(dates, times, offsets) {
  data <- import_fixture()
  data$Date <- dates; data$Time <- times; data$Offset <- offsets
  data
}

test("CSV conversion preserves stable keys, selected values and blank behaviour", {
  with_import(callback = function(path, directory) {
    input <- import_fixture()
    input_path <- file.path(directory, "source.csv")
    write.csv(input, input_path, row.names = FALSE)
    original_md5 <- tools::md5sum(input_path)
    result <- prepare_monitoring_import(path, input_path, file.path(directory, "prepared"))
    data <- read_monitoring_input(result$input)
    config <- read_monitoring_config(result$config)
    normalized <- normalize_observations(data, config)
    stopifnot(identical(data$observation_id, c("000001", "000002")), identical(data$patient_id, c("0007", "0007")),
      identical(data$episode_id, c("0012", "0012")), identical(data$observed_at, input$`Recorded at`),
      is.na(data$behaviour[1L]), normalized$data$behaviour[1L] == "unknown", !config$statistics_enabled,
      !"Patient name" %in% names(data), !"source_note" %in% names(data),
      identical(tools::md5sum(input_path), original_md5))
    receipt <- read.dcf(file.path(result$output, "import-receipt.dcf"))
    # Hashes may legitimately contain a short digit sequence also used by an ID;
    # inspect receipt fields and non-hash values rather than matching that by chance.
    stopifnot(setequal(colnames(receipt), c("Version", "Status", "TimestampMode", "InputRows", "OutputRows",
      "SelectedReportRows", "SelectedIssueCount", "InputMD5", "ImportConfigMD5", "OutputMD5")),
      !any(grepl("000001|0007|0012|DO NOT COPY|source.csv", receipt[, !grepl("MD5$", colnames(receipt)), drop = FALSE])))
  })
})

test("Explicit extras and individual behaviour labels survive the report mapping", {
  with_import(list(ExtraColumns = "source_note", BehaviourTypes = "Restlessness=Restless flag"), function(path, directory) {
    input <- import_fixture(); input$`Restless flag` <- c("YES", "")
    mapping <- read_monitoring_import_config(path)
    data <- adapt_monitoring_export(input, mapping)$data
    stopifnot(identical(data$source_note, input$source_note), !"Patient name" %in% names(data),
      identical(data$behaviour_type_001, c("YES", "")),
      identical(mapping$config$behaviour_columns, c(Restlessness = "behaviour_type_001")))
  })
})

test("Fallback values remain explicit and blank never means negative behaviour", {
  with_import(list(AwakeCalmColumn = "Calm", SleepingColumn = "Sleeping"), function(path, directory) {
    input <- import_fixture(); input$Sleep <- ""; input$Behaviour <- ""
    input$Calm <- c("Awake/Calm", ""); input$Sleeping <- c("", "Sleeping")
    result <- adapt_monitoring_export(input, read_monitoring_import_config(path))
    stopifnot(identical(result$data$sleep_state, c("", "")),
      identical(result$normalized$data$sleep_state, c("awake", "asleep")),
      identical(result$normalized$data$behaviour, c("unknown", "unknown")))
  })
})

test("Toronto spring transition accepts actual times with their supplied offsets", {
  with_import(split_settings(), function(path, directory) {
    input <- split_fixture(rep("2026-03-08", 2L), c("01:30:00", "03:30:00"), c("-05:00", "-04:00"))
    result <- adapt_monitoring_export(input, read_monitoring_import_config(path))
    stopifnot(diff(as.numeric(result$normalized$data$observed_at)) == 3600,
      identical(result$data$observed_at, c("2026-03-08T01:30:00-05:00", "2026-03-08T03:30:00-04:00")))
    input$Time[1L] <- "02:30:00"
    reject(adapt_monitoring_export(input, read_monitoring_import_config(path)), "DST|nonexistent")
  })
})

test("Toronto fall repeated clock times remain separate real instants", {
  with_import(split_settings(), function(path, directory) {
    input <- split_fixture(rep("2026-11-01", 2L), rep("01:30:00", 2L), c("-04:00", "-05:00"))
    result <- adapt_monitoring_export(input, read_monitoring_import_config(path))
    stopifnot(diff(as.numeric(result$normalized$data$observed_at)) == 3600)
    input$Offset <- "-05:00"
    reject(adapt_monitoring_export(input, read_monitoring_import_config(path)), "Duplicate patient")
  })
})

test("Fixed offset works in its season and fails across a DST change", {
  with_import(split_settings(UTCOffsetColumn = "", UTCOffset = "-05:00"), function(path, directory) {
    mapping <- read_monitoring_import_config(path)
    input <- split_fixture(rep("2026-01-02", 2L), c("08:00:00", "09:00:00"), rep("ignored", 2L))
    stopifnot(nrow(adapt_monitoring_export(input, mapping)$data) == 2L)
    input$Date[2L] <- "2026-07-02"
    reject(adapt_monitoring_export(input, mapping), "offset does not match")
  })
})

test("Exact DMY dates and minute times convert without locale assumptions", {
  with_import(split_settings(DateFormat = "%d/%m/%Y", TimeFormat = "%H:%M"), function(path, directory) {
    input <- split_fixture(c("01/08/2026", "02/08/2026"), c("08:30", "09:30"), c("-0400", "-0400"))
    result <- adapt_monitoring_export(input, read_monitoring_import_config(path))
    stopifnot(identical(result$data$observed_at, c("2026-08-01T08:30:00-0400", "2026-08-02T09:30:00-0400")))
  })
})

test("Malformed dates, serial values, invalid clocks and missing offsets are rejected", {
  with_import(split_settings(), function(path, directory) {
    mapping <- read_monitoring_import_config(path)
    invalid <- list(c("Date", "2026-02-30"), c("Date", "2026-8-01"), c("Date", "46235"),
      c("Time", "0.5"), c("Time", "08:00"), c("Time", "24:00:00"), c("Time", "08:00:60"),
      c("Offset", ""), c("Offset", "EDT"), c("Offset", "+2500"), c("Offset", "-0460"))
    for (item in invalid) {
      input <- split_fixture(rep("2026-08-01", 2L), c("08:00:00", "09:00:00"), rep("-04:00", 2L))
      input[[item[1L]]][1L] <- item[2L]
      reject(adapt_monitoring_export(input, mapping), "format|calendar|clock|offset")
    }
  })
})

test("Duplicate keys are rejected before files are created, including outside report scope", {
  with_import(list(StartDate = "2026-08-01", EndDate = "2026-08-01"), function(path, directory) {
    input <- import_fixture(); input$`Observation key`[2L] <- input$`Observation key`[1L]
    input$`Recorded at`[2L] <- "2026-09-01T13:00:00Z"
    input_path <- file.path(directory, "source.csv"); write.csv(input, input_path, row.names = FALSE)
    output <- file.path(directory, "prepared")
    reject(prepare_monitoring_import(path, input_path, output), "Duplicate observation")
    stopifnot(!dir.exists(output))
    input <- import_fixture(); input$`Recorded at`[2L] <- "2026-08-01T08:00:00-04:00"
    reject(adapt_monitoring_export(input, read_monitoring_import_config(path)), "Duplicate patient")
  })
})

test("Missing or whitespace keys are rejected and error output avoids patient values", {
  with_import(callback = function(path, directory) {
    mapping <- read_monitoring_import_config(path)
    for (key in c("Observation key", "Person key", "Admission key")) {
      input <- import_fixture(); input[[key]][1L] <- ""
      message <- reject(adapt_monitoring_export(input, mapping), "nonblank")
      stopifnot(!grepl("0007|0012", message))
    }
    input <- import_fixture(); input$`Person key`[1L] <- " 0007"
    reject(adapt_monitoring_export(input, mapping), "whitespace")
  })
})

test("Unquoted CSV identifier whitespace cannot disappear before adapter validation", {
  with_import(callback = function(path, directory) {
    input_path <- file.path(directory, "unquoted.csv")
    writeLines(c("Observation key,Person key,Admission key,Ward,Recorded at,Sleep,Behaviour",
      "000001, 0007 ,0012,Synthetic ward,2026-08-01T12:00:00Z,Awake,YES"), input_path)
    imported <- read_monitoring_input(input_path)
    stopifnot(identical(imported$`Person key`, " 0007 "))
    reject(prepare_monitoring_import(path, input_path, file.path(directory, "prepared")), "whitespace")
    stopifnot(!dir.exists(file.path(directory, "prepared")))
  })
})

test("Existing directories, source files and previous results are preserved", {
  with_import(callback = function(path, directory) {
    input_path <- file.path(directory, "source.csv"); write.csv(import_fixture(), input_path, row.names = FALSE)
    original <- tools::md5sum(input_path)
    reject(prepare_monitoring_import(path, input_path, directory), "not empty")
    reject(prepare_monitoring_import(path, input_path, input_path), "cannot be overwritten")
    output <- file.path(directory, "prepared"); dir.create(output)
    prepare_monitoring_import(path, input_path, output)
    prepared <- tools::md5sum(file.path(output, "observations.csv"))
    reject(prepare_monitoring_import(path, input_path, output), "not empty")
    stopifnot(identical(tools::md5sum(input_path), original),
      identical(tools::md5sum(file.path(output, "observations.csv")), prepared))
  })
})

test("Ambiguous modes, colliding mappings and misspelled settings fail explicitly", {
  invalid <- list(list(TimestampMode = "guess"), list(DateFormat = "%Y-%m-%d"),
    list(PatientIdColumn = "Observation key"), list(ExtraColumns = "patient_id"),
    list(BehaviourTypes = "A=flag|a=other"), list(Unexpected = "ignored"),
    list(StatisticsEnabled = "true"), split_settings(UTCOffsetColumn = "", UTCOffset = ""),
    split_settings(UTCOffset = "-0400"), split_settings(DateFormat = "%d-%b-%Y"))
  for (changes in invalid) with_import(changes, function(path, directory)
    reject(read_monitoring_import_config(path), "."))
  with_import(callback = function(path, directory) {
    input <- import_fixture(); names(input)[1L] <- "Observation.key"
    reject(adapt_monitoring_export(input, read_monitoring_import_config(path)), "literal export headings")
  })
})

test("ISO mode requires an actual calendar timestamp and explicit offset", {
  with_import(callback = function(path, directory) {
    mapping <- read_monitoring_import_config(path)
    for (timestamp in c("2026-08-01T12:00:00", "2026-02-30T12:00:00Z", "2026-08-01 12:00:00Z", " 2026-08-01T12:00:00Z")) {
      input <- import_fixture(); input$`Recorded at`[1L] <- timestamp
      reject(adapt_monitoring_export(input, mapping), "timestamp|calendar")
    }
  })
})

test("Duplicate source headings and repeated DCF fields cannot choose a value silently", {
  with_import(callback = function(path, directory) {
    input <- import_fixture(); names(input)[ncol(input)] <- "Person key"
    reject(adapt_monitoring_export(input, read_monitoring_import_config(path)), "unique|duplicate")
    cat("PatientIdColumn: Another key\n", file = path, append = TRUE)
    reject(read_monitoring_import_config(path), "exactly once")
  })
})

if (requireNamespace("openxlsx", quietly = TRUE) && requireNamespace("readxl", quietly = TRUE)) {
  test("Unencrypted XLSX input keeps text identifiers and literal source headings", {
    with_import(callback = function(path, directory) {
      input_path <- file.path(directory, "source.xlsx")
      openxlsx::write.xlsx(import_fixture(), input_path)
      result <- prepare_monitoring_import(path, input_path, file.path(directory, "prepared"))
      input <- read_monitoring_input(result$input)
      stopifnot(identical(input$observation_id, c("000001", "000002")), identical(input$patient_id, c("0007", "0007")))
    })
  })
} else cat("SKIP - XLSX import integration requires readxl and openxlsx.\n")

failures <- Filter(function(result) !is.null(result$problem), checks)
cat(length(checks) - length(failures), "/", length(checks), " import checks passed\n", sep = "")
if (length(failures)) quit(status = 1L)
