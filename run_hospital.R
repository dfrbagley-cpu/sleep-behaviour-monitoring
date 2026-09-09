# Open in RStudio and click Source, or run: Rscript --vanilla run_hospital.R
# Edit hospital/settings.R for local files. The default run is synthetic.
local({
  args <- commandArgs(trailingOnly = FALSE)
  from_command <- sub("^--file=", "", args[startsWith(args, "--file=")])
  source_files <- Filter(Negate(is.null), lapply(sys.frames(), function(frame) frame$ofile))
  script <- if (length(source_files)) tail(source_files, 1L)[[1L]] else if (length(from_command)) from_command[1L] else "run_hospital.R"
  root <- dirname(normalizePath(script, mustWork = TRUE))
  for (file in c("config.R", "synthetic.R", "analytics.R", "extended.R", "statistics.R", "raw_data.R", "report.R", "workbook.R", "pipeline.R"))
    sys.source(file.path(root, "R", file), envir = environment())
  settings_env <- new.env(parent = baseenv())
  sys.source(file.path(root, "hospital", "settings.R"), envir = settings_env)
  if (!exists("hospital_settings", envir = settings_env, inherits = FALSE)) stop("hospital/settings.R must define hospital_settings.")
  settings <- settings_env$hospital_settings
  if (!is.list(settings) || !identical(sort(names(settings)), sort(c("mode", "input_file", "config_file", "output_parent"))))
    stop("Hospital settings need mode, input_file, config_file and output_parent.")
  if (any(!vapply(settings, function(x) is.character(x) && length(x) == 1L && !is.na(x), logical(1)))) stop("Each hospital setting must be one text value.")
  if (!settings$mode %in% c("demo", "local")) stop("Hospital mode must be demo or local.")
  resolve <- function(path) {
    if (!nzchar(path)) stop("A required path in hospital/settings.R is blank.")
    if (grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)) path else file.path(root, path)
  }
  demo <- settings$mode == "demo"
  config_path <- if (demo) file.path(root, "config", "site.example.dcf") else resolve(settings$config_file)
  parent <- resolve(settings$output_parent)
  output <- tempfile(paste0(if (demo) "demo-" else "report-", format(Sys.time(), "%Y%m%d-%H%M%S"), "-"), tmpdir = parent)
  run_monitoring_pipeline(root, config_path, if (demo) NULL else resolve(settings$input_file),
    output, demo = demo, edition = "hospital", require_workbook = TRUE)
})
