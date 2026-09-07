#!/usr/bin/env Rscript
local({
  full_args <- commandArgs(trailingOnly = FALSE)
  script <- sub("^--file=", "", full_args[grepl("^--file=", full_args)])
  root <- if (length(script)) dirname(normalizePath(script[1])) else getwd()
  for (file in c("config.R", "synthetic.R", "analytics.R", "report.R")) sys.source(file.path(root, "R", file), envir = environment())
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
    config <- read_monitoring_config(config_path); config$synthetic <- demo
    input <- if (demo) make_synthetic_observations() else read_monitoring_input(opts$input)
    normalized <- normalize_observations(input, config)
    results <- summarize_observations(normalized$data, config)
    results$issues <- normalized$issues
    output <- if (!is.null(opts$output)) opts$output else file.path(root, "outputs", paste0("demo-", format(Sys.time(), "%Y%m%d-%H%M%S")))
    if (dir.exists(output) && length(list.files(output, all.files = TRUE, no.. = TRUE))) stop("Output directory is not empty. Choose a new directory to preserve earlier reports.", call. = FALSE)
    if (file.exists(output) && !dir.exists(output)) stop("Output path is a file.", call. = FALSE)
    dir.create(output, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(output)) stop("Cannot create the output directory.", call. = FALSE)
    write_monitoring_report(results, config, output)
    receipt <- data.frame(Version = monitoring_version, Synthetic = as.character(demo),
                          ConfigMD5 = unname(tools::md5sum(config_path)),
                          SourceMD5 = if (demo) "generated-from-versioned-rules" else unname(tools::md5sum(opts$input)),
                          RVersion = as.character(getRversion()), InputRows = nrow(input),
                          SelectedRows = nrow(normalized$data), stringsAsFactors = FALSE)
    write.dcf(receipt, file = file.path(output, "run-receipt.dcf"))
    if (demo) write.csv(input, file.path(output, "synthetic-observations.csv"), row.names = FALSE, na = "")
    cat("Report complete: ", normalizePath(file.path(output, "report.html")), "\n", sep = "")
    if (!requireNamespace("openxlsx", quietly = TRUE)) cat("HTML charts and CSV summaries are ready. For automatic Excel output, run Rscript --vanilla scripts/install_optional.R once.\n")
  }
  tryCatch(main(), error = function(e) { message("Unable to generate report: ", conditionMessage(e)); quit(status = 1L) })
})
