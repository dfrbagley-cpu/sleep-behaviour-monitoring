# One calculation pipeline for versioned hospital and development releases.
# No installation, network calls, global workspace clearing, or working-directory changes.
run_monitoring_pipeline <- function(root, config_path, input_path = NULL,
                                    output = NULL, demo = FALSE,
                                    edition = "development", require_workbook = FALSE) {
  if (!edition %in% c("hospital", "development")) stop("Unknown report edition.")
  if (require_workbook && !requireNamespace("openxlsx", quietly = TRUE))
    stop("Hospital Excel reports require openxlsx. Ask IT to install the approved package before running; check_setup.R lists requirements.", call. = FALSE)
  config <- read_monitoring_config(config_path)
  if (edition == "hospital" && isTRUE(config$statistics_enabled))
    stop("Hospital reports require StatisticsEnabled: false. Experimental inference belongs in development.", call. = FALSE)
  config$synthetic <- isTRUE(demo)
  input <- if (demo) make_synthetic_observations() else read_monitoring_input(input_path)
  normalized <- normalize_observations(input, config)
  results <- summarize_observations(normalized$data, config)
  extended <- extend_monitoring_analysis(input, normalized, config)
  for (name in c("behaviour", "behaviour_daily", "metric_daily", "peer_comparisons")) results[[name]] <- extended[[name]]
  results$statistics <- compute_monitoring_statistics(extended$metric_daily, config)
  results$issues <- rbind(normalized$issues, extended$issues)
  results$raw_data <- prepare_monitoring_raw_data(input, normalized$data, config)
  if (is.null(output)) output <- tempfile(paste0(if (demo) "demo-" else "report-", format(Sys.time(), "%Y%m%d-%H%M%S"), "-"), tmpdir = file.path(root, "outputs"))
  if (dir.exists(output) && length(list.files(output, all.files = TRUE, no.. = TRUE)))
    stop("Output directory is not empty. Choose a new directory to preserve earlier reports.", call. = FALSE)
  if (file.exists(output) && !dir.exists(output)) stop("Output path is a file.", call. = FALSE)
  if (!dir.exists(output) && !dir.create(output, recursive = TRUE, showWarnings = FALSE))
    stop("Cannot create the output directory.", call. = FALSE)
  written <- write_monitoring_report(results, config, output)
  if (require_workbook && !file.exists(file.path(output, "monitoring-report.xlsx")))
    stop("Excel output was not created; report run is incomplete.", call. = FALSE)
  core_paths <- sort(list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE))
  fingerprints <- data.frame(file = paste0("R/", basename(core_paths)), md5 = unname(tools::md5sum(core_paths)))
  write.csv(fingerprints, file.path(output, "software-files.csv"), row.names = FALSE)
  receipt <- data.frame(Version = monitoring_version, Edition = edition, Synthetic = as.character(demo),
    ConfigMD5 = unname(tools::md5sum(config_path)),
    SourceMD5 = if (demo) "generated-from-versioned-rules" else unname(tools::md5sum(input_path)),
    RVersion = as.character(getRversion()), InputRows = nrow(input), SelectedRows = nrow(normalized$data),
    OpenxlsxVersion = if (requireNamespace("openxlsx", quietly = TRUE)) as.character(utils::packageVersion("openxlsx")) else "not-installed",
    ReadxlVersion = if (requireNamespace("readxl", quietly = TRUE)) as.character(utils::packageVersion("readxl")) else "not-installed",
    StatisticsEnabled = as.character(config$statistics_enabled),
    Status = "completed", stringsAsFactors = FALSE)
  write.dcf(receipt, file = file.path(output, "run-receipt.dcf"))
  if (demo) write.csv(input, file.path(output, "synthetic-observations.csv"), row.names = FALSE, na = "")
  cat("Report complete: ", normalizePath(file.path(output, "report.html")), "\n", sep = "")
  if (file.exists(file.path(output, "monitoring-report.xlsx")))
    cat("Excel report: ", normalizePath(file.path(output, "monitoring-report.xlsx")), "\n", sep = "")
  invisible(list(output = normalizePath(output), results = results, receipt = receipt, files = written))
}
