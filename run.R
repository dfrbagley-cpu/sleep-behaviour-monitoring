#!/usr/bin/env Rscript
local({
  full_args <- commandArgs(trailingOnly = FALSE)
  script <- sub("^--file=", "", full_args[grepl("^--file=", full_args)])
  root <- if (length(script)) dirname(normalizePath(script[1])) else getwd()
  for (file in c("config.R", "synthetic.R", "analytics.R", "extended.R", "statistics.R", "raw_data.R", "report.R", "workbook.R", "pipeline.R")) sys.source(file.path(root, "R", file), envir = environment())
  main <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    usage <- paste("Usage: Rscript --vanilla run.R --demo [--output DIRECTORY]",
                   "   or: Rscript --vanilla run.R --config FILE --input FILE --output DIRECTORY", sep = "\n")
    if ("--help" %in% args || !length(args)) { cat(usage, "\n"); return(invisible(NULL)) }
    opts <- list(); i <- 1L
    while (i <= length(args)) {
      key <- args[i]
      if (key == "--demo") { if (!is.null(opts$demo)) stop("Duplicate --demo."); opts$demo <- TRUE; i <- i + 1L; next }
      if (!key %in% c("--config", "--input", "--output") || i == length(args) || startsWith(args[i+1L], "--")) stop(usage, call. = FALSE)
      field <- substring(key, 3L)
      if (!is.null(opts[[field]])) stop("Duplicate option: ", key, call. = FALSE)
      opts[[field]] <- args[i+1L]; i <- i + 2L
    }
    demo <- isTRUE(opts$demo)
    if (demo && (!is.null(opts$input) || !is.null(opts$config))) stop("Demo uses its own generated observations and example settings.", call. = FALSE)
    if (!demo && (is.null(opts$input) || is.null(opts$config) || is.null(opts$output))) stop(usage, call. = FALSE)
    config_path <- if (demo) file.path(root, "config", "site.example.dcf") else opts$config
    run_monitoring_pipeline(root, config_path, opts$input, opts$output,
      demo = demo, edition = "development", require_workbook = FALSE)
    if (!requireNamespace("openxlsx", quietly = TRUE)) cat("HTML charts and CSV summaries are ready. Excel output requires openxlsx.\n")
  }
  tryCatch(main(), error = function(e) { message("Unable to generate report: ", conditionMessage(e)); quit(status = 1L) })
})
