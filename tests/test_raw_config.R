# Configuration, provenance and workbook integration checks. Synthetic fixtures
# exercise the end-to-end reporting contract without assuming demo dimensions.

test("Experimental inference is opt-in and defaults to 28 days per period", {
  values <- read.dcf(file.path(repo_root, "config", "site.example.dcf"))
  omit <- c("StatisticsEnabled", "MinStatDays", "MinStatKnownPerDay", "HACLag", "Alpha", "BehaviourTypes", "MinPeerPatients")
  values <- values[, !colnames(values) %in% omit, drop = FALSE]
  path <- tempfile(fileext = ".dcf")
  tryCatch({
    write.dcf(values, path)
    config <- read_monitoring_config(path)
    expect_true(!config$statistics_enabled)
    expect_equal(config$min_stat_days, 28L)
    expect_equal(config$min_stat_known_per_day, 6L)
    expect_equal(config$hac_lag, 7L)
    expect_equal(config$alpha, 0.05)
    expect_equal(config$min_peer_patients, 3L)
    expect_equal(length(config$behaviour_columns), 0L)
  }, finally = unlink(path))
})

test("Named behaviour mappings preserve display labels and exact source headings", {
  with_config_file(list(BehaviourTypes = "Restlessness=RESTLESS_FLAG|Repeated requests=REQUESTS_FLAG"), function(path) {
    config <- read_monitoring_config(path)
    expect_equal(names(config$behaviour_columns), c("Restlessness", "Repeated requests"))
    expect_equal(unname(config$behaviour_columns), c("RESTLESS_FLAG", "REQUESTS_FLAG"))
  })
})

test("Ambiguous, reserved and core-column behaviour mappings are rejected", {
  for (mapping in c("Sleep=flag", "ANY RECORDED BEHAVIOUR=flag", "A=flag|a=other",
                     "A=flag|B=flag", "A=sleep_state", "A", "=flag", "A=")) {
    with_config_file(list(BehaviourTypes = mapping), function(path) expect_error(read_monitoring_config(path), "BehaviourTypes"))
  }
})

test("Inference and peer settings reject invalid ranges and noninteger counts", {
  invalid <- list(list(StatisticsEnabled = "yes"), list(MinStatDays = "27"), list(MinStatDays = "28.5"),
    list(MinStatKnownPerDay = "0"), list(HACLag = "-1"), list(HACLag = "1.5"),
    list(Alpha = "0"), list(Alpha = "1"), list(Alpha = "NaN"), list(MinPeerPatients = "1"))
  for (changes in invalid) with_config_file(changes, function(path) expect_error(read_monitoring_config(path)))
  with_config_file(list(StatisticsEnabled = "true", DashboardPatient = "0001", DashboardEpisode = "001", DashboardUnit = "Ward A"), function(path) {
    config <- read_monitoring_config(path)
    expect_true(config$statistics_enabled)
    expect_equal(config$dashboard_patient, "0001")
    expect_equal(config$dashboard_episode, "001")
    expect_equal(config$dashboard_unit, "Ward A")
  })
})

test("DCF values are read as literal text without evaluating code", {
  marker <- tempfile("sbm-never-execute-")
  title <- paste0("writeLines('executed', '", marker, "')")
  with_config_file(list(Title = title), function(path) {
    expect_equal(read_monitoring_config(path)$title, title)
    expect_true(!file.exists(marker))
  })
})

raw_fixture <- function() {
  data <- fixture(c("awake", "unmapped-code", "asleep", "awake", "awake", "awake"),
    patient = c("0001", "0001", "0002", "0001", "0001", "0001"),
    unit = c("Ward A", "Ward A", "Ward A", "Other ward", "Ward A", "Ward A"),
    timestamp = c("2026-08-01T08:00:00Z", "2026-08-02T08:00:00Z", "2026-08-02T09:00:00Z",
                  "2026-08-02T10:00:00Z", "2026-07-31T08:00:00Z", "2026-08-03T08:00:00Z"))
  data$observation_id <- sprintf("%06d", seq_len(nrow(data)))
  data$source_note <- c("plain baseline note", "=1+1", "peer-only-source-value", "other-ward-note", "outside-before", "outside-after")
  data$analysis_source_row <- "original column retained"
  data$`_analysis_period` <- "another original column"
  data
}

raw_config <- function() test_config(patients = "0001", units = "Ward A")

test("Raw export retains exact selected source fields and collision-safe audit columns", {
  input <- raw_fixture()
  config <- raw_config()
  normalized <- normalize_observations(input, config)
  raw <- prepare_monitoring_raw_data(input, normalized$data, config)
  expect_equal(raw[names(input)], input[1:2, , drop = FALSE])
  expect_equal(attr(raw, "derived_prefix"), "__analysis_")
  expect_equal(raw$`__analysis_source_row`, 1:2)
  expect_equal(raw$`__analysis_period`, c("Baseline", "Report"))
  expect_equal(raw$`__analysis_sleep_state`, c("awake", "unknown"))
  expect_equal(raw$sleep_state, c("awake", "unmapped-code"))
  expect_equal(raw$observation_id, c("000001", "000002"))
  expect_equal(raw$patient_id, c("0001", "0001"))
  expect_equal(anyDuplicated(names(raw)), 0L)
  expect_true(all(vapply(raw[names(input)], is.character, logical(1L))))
})

test("Raw scope excludes peers and outside records while retaining eligible ward reference rows", {
  input <- raw_fixture()
  config <- raw_config()
  normalized <- normalize_observations(input, config)
  expect_equal(normalized$data$source_row, 1:2)
  expect_equal(normalized$reference_data$source_row, 1:3)
  raw <- prepare_monitoring_raw_data(input, normalized$data, config)
  expect_true(!any(raw$source_note %in% input$source_note[3:6]))
  expect_true(all(normalized$issues$row %in% normalized$data$source_row))
})

test("Raw provenance mapping rejects noninteger, missing, duplicate and out-of-range rows", {
  input <- raw_fixture()
  config <- raw_config()
  data <- normalize_observations(input, config)$data
  for (rows in list(c(1L, NA_integer_), c(1L, 1L), c(0L, 2L), c(1L, nrow(input) + 1L),
                    c(1.5, 2), c(1, Inf), c("1", "2"))) {
    broken <- data
    broken$source_row <- rows
    expect_error(prepare_monitoring_raw_data(input, broken, config), "source-row")
  }
})

if (requireNamespace("openxlsx", quietly = TRUE)) {
  test("Workbook provides four ordered visible sheets, combined charts and filterable raw rows", {
    with_report_directory(function(output_dir) {
      input <- raw_fixture()
      config <- raw_config()
      result <- report_results(input, config)
      path <- write_dashboard_workbook(result, config, output_dir)
      expect_true(file.exists(path))
      sheets <- c("Dashboard", "Expanded analytics", "Raw data", "Documentation")
      expect_equal(openxlsx::getSheetNames(path), sheets)
      wb <- openxlsx::loadWorkbook(path)
      expect_equal(openxlsx::sheetVisibility(wb), rep("visible", 4L))
      entries <- unzip(path, list = TRUE)$Name
      expect_true(sum(grepl("^xl/media/.*[.]png$", entries)) >= 2L)
      xml_dir <- tempfile("sbm-workbook-xml-")
      dir.create(xml_dir)
      on.exit(unlink(xml_dir, recursive = TRUE), add = TRUE)
      unzip(path, exdir = xml_dir)
      # read.xlsx can tolerate a malformed nested worksheet root that Excel and
      # LibreOffice cannot render. Check the exact corruption seen during QA.
      for (sheet_file in list.files(file.path(xml_dir, "xl", "worksheets"), pattern = "^sheet[0-9]+[.]xml$", full.names = TRUE)) {
        xml <- paste(readLines(sheet_file, warn = FALSE), collapse = "")
        expect_equal(length(regmatches(xml, gregexpr("<worksheet(?:[[:space:]>])", xml, perl = TRUE))[[1L]]), 1L)
        expect_equal(length(regmatches(xml, gregexpr("</worksheet>", xml, fixed = TRUE))[[1L]]), 1L)
      }
      raw_xml <- paste(readLines(file.path(xml_dir, "xl", "worksheets", "sheet3.xml"), warn = FALSE), collapse = "")
      expect_true(grepl('state="frozen"', raw_xml, fixed = TRUE))
      expect_true(grepl("<tableParts", raw_xml, fixed = TRUE))
      table_files <- list.files(file.path(xml_dir, "xl", "tables"), pattern = "[.]xml$", full.names = TRUE)
      table_xml <- vapply(table_files, function(file) paste(readLines(file, warn = FALSE), collapse = ""), character(1L))
      source_table <- table_xml[grepl('name="observation_id"', table_xml, fixed = TRUE)]
      expect_equal(length(source_table), 1L)
      expect_true(grepl("<autoFilter", source_table, fixed = TRUE))
      exported <- openxlsx::read.xlsx(path, sheet = "Raw data", startRow = 6L, check.names = FALSE)
      expect_equal(nrow(exported), 2L)
      expect_equal(exported$observation_id, c("000001", "000002"))
      expect_equal(exported$patient_id, c("0001", "0001"))
      expect_equal(exported$source_note, c("plain baseline note", "'=1+1"))
      expect_equal(exported$sleep_state, c("awake", "unmapped-code"))
      expect_equal(exported$`__analysis_period`, c("Baseline", "Report"))
      expect_true(!any(grepl("peer-only-source-value", unlist(exported), fixed = TRUE)))
      expect_true(!grepl("<f>", raw_xml, fixed = TRUE))
      dashboard <- openxlsx::read.xlsx(path, sheet = "Dashboard", colNames = FALSE)
      expect_true(any(grepl("0001", unlist(dashboard), fixed = TRUE)))
      expect_true(any(grepl("Sleep and behaviour over time", unlist(dashboard), fixed = TRUE)))
      expect_true(any(grepl("Evidence of change", unlist(dashboard), fixed = TRUE)))
    })
  })

  test("Dashboard rejects an unmatched configured focus instead of displaying another person", {
    config <- raw_config()
    result <- report_results(raw_fixture(), config)
    config$dashboard_patient <- "absent-patient"
    with_report_directory(function(output_dir)
      expect_error(write_dashboard_workbook(result, config, output_dir), "selection does not match"))
  })
} else cat("SKIP - Excel integration checks require optional openxlsx\n")
