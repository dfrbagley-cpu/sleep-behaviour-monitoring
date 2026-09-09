# Read-only, offline check. Does not install or update anything.
local({
  cat("Sleep & Behaviour Monitoring | Hospital setup\n")
  cat("R: ", as.character(getRversion()), "\n", sep = "")
  for (package in c("openxlsx", "readxl")) {
    available <- requireNamespace(package, quietly = TRUE)
    cat(package, ": ", if (available) as.character(utils::packageVersion(package)) else "MISSING", "\n", sep = "")
  }
  cat("PNG charts: ", if (capabilities("png")) "available" else "unavailable", "\n", sep = "")
  cat("openxlsx is required for hospital reports; readxl is needed only for XLSX input.\n")
  cat("Ask IT to preinstall approved packages on the computer running R. Copying this folder does not install R or its packages.\n")
  cat("Run the synthetic demo next to check charts, workbook generation and output-folder access.\n")
})
