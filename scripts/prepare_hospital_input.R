#!/usr/bin/env Rscript
# Run locally: Rscript --vanilla scripts/prepare_hospital_input.R --config import.dcf --input export.csv --output prepared/new-run
local({
  args <- commandArgs(trailingOnly = FALSE)
  from_command <- sub("^--file=", "", args[startsWith(args, "--file=")])
  source_files <- Filter(Negate(is.null), lapply(sys.frames(), function(frame) frame$ofile))
  script <- if (length(source_files)) tail(source_files, 1L)[[1L]] else if (length(from_command)) from_command[1L] else "scripts/prepare_hospital_input.R"
  root <- dirname(dirname(normalizePath(script, mustWork = TRUE)))
  args <- commandArgs(trailingOnly = TRUE)
  usage <- "Usage: Rscript --vanilla scripts/prepare_hospital_input.R --config import.dcf --input export.csv --output prepared/new-run"
  if (identical(args, "--help")) {
    cat(usage, "\n")
  } else {
    if (length(args) != 6L || !setequal(args[c(1L, 3L, 5L)], c("--config", "--input", "--output")))
      stop(usage, call. = FALSE)
    settings <- stats::setNames(as.list(args[c(2L, 4L, 6L)]), args[c(1L, 3L, 5L)])
    if (any(!nzchar(unlist(settings))) || any(startsWith(unlist(settings), "--"))) stop(usage, call. = FALSE)
    for (file in c("config.R", "analytics.R", "import.R")) sys.source(file.path(root, "R", file), envir = environment())
    result <- prepare_monitoring_import(settings[["--config"]], settings[["--input"]], settings[["--output"]])
    cat("Local import validated. Set hospital/settings.R input_file and config_file to:\n",
      result$input, "\n", result$config, "\n", sep = "")
    cat("Review data-quality issues in the generated report before operational use.\n")
  }
})
