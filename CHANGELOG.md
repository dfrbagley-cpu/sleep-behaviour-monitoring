# Changelog

## 0.1.0 — Synthetic development preview

- Replaced repeated patient-specific blocks with shared functions for all selected patient admissions and units.
- Added one configuration file for source columns, observation codes, timezone, reporting dates, time bands, baseline, and patient/unit selections.
- Added automatically generated HTML charts and optional Excel reports with chart images. The separate spreadsheet paste step is no longer part of this workflow.
- Added deterministic synthetic observations for six patients across two fictional units.
- Standardized behaviour percentages to explicitly awake checks with known behaviour status; retained missing and conflicting values as unknown.
- Added strict duplicate, header, identifier, timestamp, date-window, and configuration validation.
- Added fixed baseline comparisons and separate pooled-observation and equal-admission unit summaries.
- Made observation proportions the default. Standardized sleep-hours estimates are optional and explicitly labelled as estimates.
- Removed workstation-specific execution, hardcoded credentials, automatic raw-data exports, and dependence on desktop Excel for the core HTML report.
- Added automated regression checks and repeatable synthetic report generation.

The former visual spreadsheet template has not been supplied. Exact chart/formula parity, local data mapping, expected observation schedules, and clinical validation remain outstanding. Reuse licensing is pending.
