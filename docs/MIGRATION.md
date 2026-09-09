# Migration and validation status

The supplied legacy R script has been statically reviewed and a configurable,
organization-neutral implementation built around generated observations. The
original script and its embedded local settings are not public release files.
Public demonstrations and future local use share the same calculation functions.
Licensing is pending; see [LICENSING.md](../LICENSING.md).

## Implemented in this prototype

| Area | Current behaviour |
| --- | --- |
| Setup | One-command base-R demo; optional packages for Excel input and output |
| Input | CSV or unencrypted XLSX; column/code mappings in a non-executable DCF file |
| Identity | Stable observation, patient and admission IDs; configurable unit field |
| Validation | Required columns, identifiers, strict timestamps and duplicates checked; state issues remain visible |
| Scope | Units, patients and inclusive report dates; local reporting-day boundary and exhaustive time bands |
| Sleep | Asleep proportion among point observations with known sleep state |
| Behaviour | Behaviour proportion among confirmed-awake observations with known behaviour status |
| Individual behaviours | Optional separate source flags, each with its own known-status denominator |
| Baseline | Earlier period matched by patient, admission, unit and band; counts and recorded completeness gate changes |
| Aggregation | Patient/admission, daily/hourly, pooled unit and equal-admission summaries |
| Ward peers | Descriptive comparisons with eligible other people in the same unit/report dates; index person excluded across all admissions |
| Statistical panel | Daily-mean effects and test status; experimental inference disabled by default because its calibration is not established |
| Output | HTML charts/tables, CSV summaries, optional four-sheet Excel workbook with charts and run receipt |
| Raw review | Filterable selected source rows and derived fields in the workbook; original columns retained |

Pasting results into a separate Excel template is replaced by direct generation.
The workbook follows the requested order: Dashboard, Expanded analytics, Raw data,
Documentation. Sleep and behaviour appear together over time on the dashboard;
the expanded page adds individual behaviours, personal history and ward peers.
The former template's exact layout and formulas have not been compared. Its absence
does not prevent using and reviewing the new four-sheet design.

## Intentional numerical changes

The [source review](SOURCE_REVIEW.md) documents confirmed issues. Major changes are
consistent behaviour eligibility, explicit unknown states, conflicting sleep
handling, matching patient/unit/date scope and correct selection of any number of
patients.

The default report does not label a sleep proportion multiplied by clock hours as
measured sleep. `EstimateHours: true` exposes an optional standardized projection
for comparison work only. It neither infers actual sleep duration nor compensates
for missing observations. Keep the default `false` for routine review.

Blank behaviour remains unknown even when an awake/calm fallback flag identifies
sleep state. Whether a local export uses blanks to mean an explicitly recorded
absence remains unresolved. Confirm that meaning before changing an adapter; do
not silently redefine missing values as absence in the shared metric.

Overall behaviour and individual behaviour flags remain separate source measures.
No flags are filled from other flags, and overlapping behaviours are allowed.
Daily-mean changes weight days equally; pooled observation changes weight each
known observation equally. Both are labelled to make the different questions clear.

The statistical panel does not provide established significance testing. The
experimental HAC method is opt-in and showed poor false-positive calibration in
simulation checks. See [STATISTICS.md](STATISTICS.md). Descriptive ward comparisons
are not tests and do not account for case mix.

## Remaining local verification

1. **Confirm the observation contract.** Establish whether rows are point checks,
   intervals or a mixture. This release implements point checks only. Verify IDs,
   admission boundaries, transfers, code meanings and timestamp construction.
2. **Review the report workflow.** Check the focused dashboard, combined chart,
   expanded comparisons, raw filters and dictionary against reviewer needs. A
   blank former template with fictional inputs can support exact comparison if
   desired. Regenerate reports to update calculations; workbook edits do not
   recalculate the generated charts or analytics.
3. **Verify synthetic expectations.** Use hand-calculated cases for missing and
   conflicting states, zero denominators, duplicate rejection, time boundaries,
   filtering, unequal observation counts and baseline eligibility. Legacy output
   is not the acceptance target where its calculation contains a confirmed error.
4. **Compare local reports.** Run an approved local comparison with representative
   exports. Reconcile material differences before replacing the working tool.
5. **Approve the intended workflow.** Confirm report review, storage/sharing,
   decision uses and version-change acceptance. Regression checks alone do not
   establish clinical validation.
6. **Resolve inferential suitability separately.** Leave experimental statistics
   disabled until a suitable method and representative validation plan have been
   reviewed. Do not interpret unavailable tests or non-significant experimental
   output as evidence that no meaningful change occurred.

## Deferred capabilities

| Capability | Dependency |
| --- | --- |
| Measured or interval-based sleep duration | Verified start/end semantics, overlaps and elapsed-time rules |
| Expected-check coverage and missed checks | Actual schedules and admission/discharge/leave eligibility |
| Clinical alerts, prediction or causal interpretation | Defined use case, appropriate study design and clinical validation |
| Calibrated significance testing | Suitable longitudinal method, recording assumptions and simulation/empirical validation |
| Direct connections and scheduled reports | Chosen local integration and operational access model |
| Encrypted exports or hosted multi-user use | Defined deployment, identity and data-protection approach |

Recorded-field completeness is implemented; schedule coverage is not. Fully
populated received rows can still omit checks never supplied. Baseline count and
completeness settings are software defaults, not clinically established thresholds.
Admission-weighted and observation-weighted unit results answer different questions
and remain separately labelled.

The raw-data worksheet now contains every original column from selected report and
baseline rows. Review the export scope and source columns before distributing it.
Ward benchmarks can use other same-unit records that are absent from a report
restricted to one person; the report's peer counts document that broader reference
scope without including unselected raw records.

Keep local adaptation outside shared calculations. Changes to observation semantics
or formulas need a documented reason, synthetic expected results and a version
change. Prioritize a verified local import and report comparison before adding
analytical complexity.
