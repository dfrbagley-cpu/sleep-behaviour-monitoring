# Run once when Excel input/output is needed. The base-R HTML demo needs no packages.
packages <- c("readxl", "openxlsx")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
# Respect an approved configured repository and CI's binary package mirror.
# Plain R sessions with no repository selected use the standard CRAN fallback.
repos <- getOption("repos")
if (is.null(repos) || !length(repos) || any(repos == "@CRAN@")) repos <- c(CRAN = "https://cloud.r-project.org")
if (length(missing)) install.packages(missing, repos = repos)
if (!all(vapply(packages, requireNamespace, logical(1), quietly = TRUE))) stop("Excel packages could not be installed.")
cat("Excel input and report export are available.\n")
