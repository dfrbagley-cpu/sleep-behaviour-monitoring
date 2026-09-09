#!/usr/bin/env Rscript
# Parity and release-boundary checks with a small hand-computable fixture.
args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[startsWith(args, "--file=")])
root <- if (length(script)) dirname(dirname(normalizePath(script[1L]))) else normalizePath(".")
for (file in c("config.R", "synthetic.R", "analytics.R", "extended.R", "statistics.R", "raw_data.R", "report.R", "workbook.R", "pipeline.R")) source(file.path(root, "R", file))
local({
  temporary <- tempfile("edition checks ")
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
  input <- data.frame(observation_id = paste0("O", 1:4), patient_id = "001", episode_id = "E1",
    unit = "Test ward", observed_at = c("2026-07-01T12:00:00Z", "2026-07-01T13:00:00Z",
    "2026-07-29T12:00:00Z", "2026-07-29T13:00:00Z"), sleep_state = c("Awake", "Asleep", "Awake", "Awake"),
    behaviour = c("YES", "NO", "NO", "YES"), awake_calm = "", sleeping = "")
  input_path <- file.path(temporary, "input.csv")
  write.csv(input, input_path, row.names = FALSE)
  config_path <- file.path(root, "config", "hospital.example.dcf")
  hospital <- run_monitoring_pipeline(root, config_path, input_path, file.path(temporary, "hospital"),
    edition = "hospital", require_workbook = requireNamespace("openxlsx", quietly = TRUE))
  development <- run_monitoring_pipeline(root, config_path, input_path, file.path(temporary, "development"))
  stopifnot(identical(hospital$results, development$results))
  stopifnot(hospital$receipt$Edition == "hospital", development$receipt$Edition == "development")
  stopifnot(hospital$receipt$InputRows == 4L, hospital$receipt$SelectedRows == 4L)
  total <- hospital$results$patient[hospital$results$patient$band == "Total", ]
  stopifnot(total$sleep_pct == 0, total$behaviour_pct == 50)
  stopifnot(!file.exists(file.path(hospital$output, "synthetic-observations.csv")))
  cat("PASS - Both editions share identical calculations; hand counts and receipt scope agree.\n")
  rejected <- function(expr, pattern) {
    message <- tryCatch({force(expr); ""}, error = function(e) conditionMessage(e))
    stopifnot(nzchar(message), grepl(pattern, message, fixed = TRUE))
  }
  rejected(run_monitoring_pipeline(root, config_path, input_path, hospital$output), "not empty")
  stopifnot(file.exists(file.path(hospital$output, "run-receipt.dcf")))
  cat("PASS - Previous report folders are preserved.\n")
  experimental <- file.path(temporary, "experimental.dcf")
  writeLines(sub("StatisticsEnabled: false", "StatisticsEnabled: true", readLines(config_path), fixed = TRUE), experimental)
  blocked <- file.path(temporary, "blocked")
  rejected(run_monitoring_pipeline(root, experimental, input_path, blocked, edition = "hospital"), "StatisticsEnabled: false")
  stopifnot(!dir.exists(blocked))
  cat("PASS - Hospital experimental inference is rejected before report creation.\n")
  hashes <- read.csv(file.path(hospital$output, "software-files.csv"))
  stopifnot(nrow(hashes) == length(list.files(file.path(root, "R"), pattern = "[.]R$")), all(nchar(hashes$md5) == 32))
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    workbook <- file.path(hospital$output, "monitoring-report.xlsx")
    stopifnot(identical(openxlsx::getSheetNames(workbook), c("Dashboard", "Expanded analytics", "Raw data", "Documentation")))
    cat("PASS - Hospital Excel output has all four requested sheets.\n")
  } else cat("SKIP - Excel package absent; workbook generation checked in the Excel-enabled job.\n")
})
