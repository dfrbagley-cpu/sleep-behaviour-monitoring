#!/usr/bin/env Rscript
local({
  full <- commandArgs(trailingOnly = FALSE)
  script <- sub("^--file=", "", full[grepl("^--file=", full)])
  root <- if (length(script)) dirname(dirname(normalizePath(script[1L]))) else normalizePath(".")
  for (file in c("config.R", "synthetic.R", "analytics.R", "extended.R"))
    sys.source(file.path(root, "R", file), envir = environment())
  for (file in c("analysis.R", "report.R")) sys.source(file.path(root, "advanced", file), envir = environment())
  main <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    usage <- paste("Usage: Rscript --vanilla advanced/run.R --demo [--output DIRECTORY]",
      "   or: Rscript --vanilla advanced/run.R --config FILE --input FILE --demographics FILE --output DIRECTORY [--policy FILE]", sep = "\n")
    if (!length(args) || "--help" %in% args) { cat(usage, "\n"); return(invisible(NULL)) }
    opts <- list(); i <- 1L
    while (i <= length(args)) {
      key <- args[i]
      if (key == "--demo") {
        if (!is.null(opts$demo)) stop("Duplicate --demo.", call. = FALSE)
        opts$demo <- TRUE; i <- i + 1L; next
      }
      if (!key %in% c("--config", "--input", "--demographics", "--output", "--policy") ||
          i == length(args) || startsWith(args[i + 1L], "--")) stop(usage, call. = FALSE)
      field <- substring(key, 3L)
      if (!is.null(opts[[field]])) stop("Duplicate option: ", key, call. = FALSE)
      opts[[field]] <- args[i + 1L]; i <- i + 2L
    }
    demo <- isTRUE(opts$demo)
    if (demo && any(c("config", "input", "demographics") %in% names(opts)))
      stop("Demo uses its own synthetic observations and demographics.", call. = FALSE)
    if (!demo && !all(c("config", "input", "demographics", "output") %in% names(opts))) stop(usage, call. = FALSE)
    config_path <- if (demo) file.path(root, "config", "site.example.dcf") else opts$config
    policy_path <- if (is.null(opts$policy)) file.path(root, "advanced", "research-policy.dcf") else opts$policy
    config <- read_monitoring_config(config_path); config$synthetic <- demo
    policy <- advanced_policy(policy_path)
    input <- if (demo) make_synthetic_observations() else read_monitoring_input(opts$input)
    if (!demo && tolower(tools::file_ext(opts$demographics)) != "csv") stop("Demographics must be a CSV file.", call. = FALSE)
    demographics <- if (demo) make_synthetic_demographics() else read_monitoring_input(opts$demographics)
    normalized <- normalize_observations(input, config)
    joined <- join_demographics(normalized$data, demographics)
    cohorts <- advanced_cohorts(joined$data, config, policy)
    extended <- extend_monitoring_analysis(input, normalized, config)
    backtest <- advanced_backtest(extended$metric_daily, config, policy)
    output <- if (!is.null(opts$output)) opts$output else file.path(root, "outputs", paste0("research-demo-", format(Sys.time(), "%Y%m%d-%H%M%S")))
    if (file.exists(output) && !dir.exists(output)) stop("Output path is a file.", call. = FALSE)
    if (dir.exists(output) && length(list.files(output, all.files = TRUE, no.. = TRUE)))
      stop("Output directory is not empty. Choose a new directory to preserve earlier reports.", call. = FALSE)
    dir.create(output, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(output)) stop("Cannot create the output directory.", call. = FALSE)
    write_advanced_report(cohorts, joined, backtest, rbind(normalized$issues, extended$issues), config, policy, output)
    hash <- function(path) unname(tools::md5sum(path))
    sources <- c(file.path(root, "R", c("config.R", "synthetic.R", "analytics.R", "extended.R")),
      file.path(root, "advanced", c("run.R", "analysis.R", "report.R")))
    advanced_csv(data.frame(source = c(paste0("R/", basename(sources[1:4])), paste0("advanced/", basename(sources[5:7]))),
      md5 = vapply(sources, hash, character(1L))), file.path(output, "source-manifest.csv"))
    receipt <- data.frame(CoreVersion = monitoring_version, ResearchVersion = "0.1.0", Synthetic = as.character(demo),
      ConfigMD5 = hash(config_path), PolicyMD5 = hash(policy_path), SourceMD5 = if (demo) "versioned-synthetic-generator" else hash(opts$input),
      DemographicsMD5 = if (demo) "versioned-fictional-demographics" else hash(opts$demographics), RVersion = as.character(getRversion()),
      HoldoutStart = as.character(backtest$holdout_start), HoldoutEnd = as.character(backtest$holdout_end),
      ForecastStatus = "disabled", stringsAsFactors = FALSE)
    write.dcf(receipt, file.path(output, "research-receipt.dcf"))
    if (demo) {
      advanced_csv(input, file.path(output, "synthetic-observations.csv"))
      advanced_csv(demographics, file.path(output, "synthetic-demographics.csv"))
    }
    cat("Research report complete: ", normalizePath(file.path(output, "research-report.html")), "\n", sep = "")
    cat("Retrospective baseline evaluation only. Pending next-day forecasts remain disabled.\n")
  }
  tryCatch(main(), error = function(e) { message("Unable to generate research report: ", conditionMessage(e)); quit(status = 1L) })
})
