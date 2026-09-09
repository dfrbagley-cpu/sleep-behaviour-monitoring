# Two editions, one calculation engine

Updated 2026-09-09 for version 0.4.0. The hospital package and advanced development
project share the versioned `R/` calculation and reporting modules. They are two
release profiles built from the same source version.

| | Hospital R Tool | Advanced Development Version |
| --- | --- | --- |
| Primary user | Analyst preparing a clinical review | Analyst or researcher evaluating additional analyses |
| Delivery | Copyable ZIP; R/RStudio on an approved workstation | Public GitHub project and development ZIP |
| Entry point | `run_hospital.R` | `run.R` for monitoring; `advanced/run.R` for research |
| Data | Local CSV or unencrypted Excel after mapping | Generated demo or explicitly supplied local files |
| Reporting | Four-sheet Excel, HTML, descriptive changes and ward context | Shared monitoring reports; separate research HTML and CSV outputs |
| Demographics | Not required | Optional values by patient/admission; unknown values retained |
| Prediction | Excluded from distribution | Retrospective baseline evaluation; no prospective clinical scores |
| Changes | Manual versioned release after local acceptance | Iterative development and regression checks |

## Current implementation

`run.R` and `run_hospital.R` call `R/pipeline.R`. The hospital runner requires Excel
output and rejects experimental significance settings. The package builder copies
the same core modules into both packages, verifies that they match and writes
SHA-256 manifests. Advanced research files are excluded from the hospital ZIP.

The [hospital input adapter](IMPORT_ADAPTER.md) prepares explicitly mapped CSV or
unencrypted XLSX exports and a matching reporting configuration. Separate date
and time fields require declared formats and explicit UTC offsets. The adapter
checks them against the chosen time zone; it does not infer ambiguous timestamps
or supply missing admission identifiers.

`advanced/run.R` reuses shared normalization and daily metric definitions. Its
demographic slice is **stratification**, not case-mix adjustment. Its backtest
compares yesterday's recorded percentage with an equally weighted seven-day mean
on paired eligible next-day targets, using only prior dates. Neither method is a
fitted demographic model. The research command creates its own HTML and CSV
outputs; run the monitoring command separately for the four-sheet workbook.

## Priority order

1. **Local import and report acceptance.** Resolve actual identifiers, timestamps,
   blank codes and encrypted-export handling. Reconcile material differences
   against representative reports before replacing the working hospital tool.
2. **Demographic context and data quality.** Evaluate missing values and small
   cohorts. Define the unit of analysis and covariates available at the time of a
   decision before attempting adjusted comparisons.
3. **One useful predictive question.** Agree which advance warning would change
   a clinical review or action, its time horizon and an acceptable error burden.
   Evaluate simple historical baselines first.
4. **Model development when justified.** Add suitable longitudinal methods and
   predictors only after provenance, timing and outcome definitions are reliable.
5. **Validation before operational forecasts.** Evaluate later periods, new
   patients, other wards and subgroup performance. Keep model evaluation separate
   from routine reporting releases.

Software checks and synthetic demonstrations do not establish clinical validity,
local compatibility or commercial demand. A useful next adoption test is a
structured local report review: can the intended reviewer answer their existing
questions, trace an unexpected value and complete the review with less manual work?
Record the baseline effort and acceptance criteria before evaluating the new tool.

## Stop conditions

- **Shared calculations diverge:** stop the release until edition parity is restored.
- **Export meanings are unresolved:** pause migration until material discrepancies
  in identifiers, observation states and timestamps are explained.
- **Recording practices drive apparent predictions:** examine missingness and
  documentation changes before interpreting model results.
- **Complexity adds no useful improvement:** retain the descriptive workflow and
  simple baselines; do not add predictors merely to enlarge the feature list.
- **Unsupported cohorts produce misleading comparisons:** keep affected rates
  suppressed and resolve the evidence gap before making stronger claims.

## Public project boundary

On 2026-09-09 the owner explicitly authorized public development and publication
so interviewers can inspect the implementation and discuss the work. This
supersedes the earlier instruction to keep this repository private.

Public files and release examples use generated fictional data. The original
hospital script, real observations, local configuration, reports and credentials
are outside the publication boundary. Public availability does not establish a
reuse licence; [licensing remains pending](../LICENSING.md).

The public rebuild is distinct from the author's earlier hospital-used tool.
It does not claim hospital acceptance, prospective prediction validation or
integration with other proprietary projects.
