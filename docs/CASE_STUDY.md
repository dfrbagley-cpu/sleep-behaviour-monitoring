# From a manual reporting workflow to two reproducible editions

## Problem and users

The author's earlier hospital-used R tool summarized inpatient sleep and behaviour
observations for clinical and program review. Its final step required copying
calculated values into a separate Excel template to produce charts. That made
the reporting workflow dependent on manual transfer and a second set of report
assets.

This repository is a separate, organization-neutral rebuild using generated
fictional records. It replaces that transfer with direct generation of charts,
tables and a four-sheet workbook. The public rebuild itself has not been deployed
or clinically validated. No measured time savings or patient outcome improvement
are claimed.

The immediate user is the analyst preparing the report. Clinical reviewers need
the summary and trends; analysts need the observations, definitions and settings
behind a result. Those needs shaped the worksheet order: Dashboard, Expanded
analytics, Raw data, Documentation.

## Product decision: preserve the practical delivery route

A shared-drive R tool fits the existing file-based workflow. A separate
development entry point allows demographic summaries and forecast evaluation to
progress without adding research dependencies to routine hospital reporting.

Both editions ship from the same calculation modules. The package builder uses
an explicit file list, excludes advanced files from the hospital ZIP and verifies
that shared files have the same SHA-256 hashes. Local adoption still requires
approved R dependencies, verified import mappings and report acceptance.

The [input adapter](IMPORT_ADAPTER.md) supports explicit export mappings and
separate date/time fields with declared formats and offsets. Checking those
offsets against the configured time zone prevents a fixed-offset assumption from
silently moving observations across reporting periods during daylight saving.
It does not guess missing patient/admission identifiers or decrypt workbooks.

## Engineering decisions worth discussing

| Decision | Why it matters | Implementation and evidence |
| --- | --- | --- |
| Normalize observations once | Inconsistent eligibility rules can make time bands disagree even when they use the same records | `R/analytics.R`; hand-calculated denominator fixtures in `tests/run_tests.R` |
| Preserve unknown and conflicting states | Missing charting must not silently become a documented absence | Shared normalization and explicit counts; missing/conflict regression cases |
| Use patient, admission and unit keys | Returning admissions and ward transfers need defined comparison boundaries | Matched baseline selection; index patient excluded across all admissions in ward-peer comparisons |
| Separate pooled and admission-weighted summaries | Frequent charting otherwise gives some admissions more influence without making that weighting visible | Labelled aggregation methods and contributing counts |
| Generate the whole report directly | Analysts can regenerate tables and visuals from the same configuration and source rows | `R/pipeline.R`, `R/report.R` and `R/workbook.R` |
| Keep site mappings outside formulas | Source-system column differences should not create another fork of the calculation engine | Non-executable DCF mappings and a single versioned core |
| Record inputs and preserve earlier outputs | Reviewers need to identify what produced a report | Version/configuration/input fingerprints, run receipts and rejection of nonempty output directories |
| Treat untrusted labels as data | Uploaded labels should not become HTML markup or spreadsheet formulas | HTML escaping and formula-prefix neutralization; targeted regression cases |

The [source review](SOURCE_REVIEW.md) explains intentional differences from the
earlier script. Historical outputs are useful for understanding the workflow;
they are not the numerical acceptance target where a documented calculation
defect needs correction.

## Statistical restraint is part of the implementation

Point observations support recorded proportions. They do not independently
establish sleep duration or a medication effect. The report therefore exposes
the numerator, denominator and missingness and distinguishes observed change
from an explanation for that change.

An experimental inference method remains disabled by default after simulation
checks showed poor false-positive calibration. The hospital runner rejects
enabling it. The daily comparison panel still reports mean changes and available
days. The [statistics note](STATISTICS.md) documents the method, evidence and limits.

The advanced edition introduces three specific foundations:

1. **Auditable demographic joins.** One demographic record per patient/admission,
   duplicate-key rejection, unchanged observation counts, and Unknown groups for
   missing matches. Rates are suppressed below the contributor threshold.
2. **A chronological backtest.** The final 14 configured calendar days form the
   evaluation window. Yesterday's value and the previous seven-day mean are
   compared on exactly the same eligible targets. Missing dates do not become
   observed outcomes, and history does not cross admissions or units.
3. **Visible evaluation limits.** Mean absolute error uses percentage points;
   excluded targets and cohort counts are reported. Demographic labels are not
   predictors, and no prospective forecasts are produced.

These are testable foundations for further analysis. They are not evidence that
a predictive clinical product is ready.

## What is verified, and what remains unresolved

Automated checks use synthetic cases with independently specified expectations.
They cover normalization, scope and time boundaries, report exports, edition
parity, demographic joins and absence of future-data leakage. The CI workflow
runs on Linux and Windows and builds the reports and distribution packages.

Remaining acceptance work includes the hospital's actual timestamp and identifier
mapping, encrypted-export handling, meaning of blanks, report review and local
runtime compatibility. The exact former workbook has not been compared. Expected
check schedules, demographic adjustment and clinical prediction remain further
work with separate data and validation requirements.

## Questions for an engineering or product discussion

- What should one observation mean, and which fields establish a valid denominator?
- When should an unexplained data-quality issue stop a run versus remain visible
  in the report?
- How can two delivery routes evolve while preserving consistent calculations?
- Which predictive outcome would change a reviewer's action enough to justify
  collecting more data and maintaining a model?
- What local acceptance evidence is needed before replacing an established workflow?

For a reproducible walkthrough, run the two demo commands in the
[README](../README.md), inspect a dashboard comparison, then follow its fields
through the raw-data worksheet and metric definitions. The
[edition roadmap](TWO_EDITIONS.md) gives the next development decisions.
