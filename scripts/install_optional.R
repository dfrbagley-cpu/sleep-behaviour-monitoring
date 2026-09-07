# Run once when Excel input/output is needed. The base-R HTML demo needs no packages.
packages <- c("readxl", "openxlsx")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
if (!all(vapply(packages, requireNamespace, logical(1), quietly = TRUE))) stop("Excel packages could not be installed.")
cat("Excel input and report export are available.\n")
