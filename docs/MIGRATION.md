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
| Baseline | Earlier period matched by patient, admission, unit and band; counts and recorded completeness gate changes |
| Aggregation | Patient/admission, daily/hourly, pooled unit and equal-admission summaries |
| Output | HTML charts/tables, CSV summaries, optional Excel workbook with charts and run receipt |

Pasting results into a separate Excel template is replaced by direct generation.
That template was not supplied, so its exact chart layout, formulas and final
outputs have not been reproduced or verified.

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

## Remaining local verification

1. **Confirm the observation contract.** Establish whether rows are point checks,
   intervals or a mixture. This release implements point checks only. Verify IDs,
   admission boundaries, transfers, code meanings and timestamp construction.
2. **Review the former presentation.** Supply a blank Excel template with fictional
   inputs for exact visual/formula comparison. Preserve useful review workflows
   while explaining differences caused by corrected calculations.
3. **Verify synthetic expectations.** Use hand-calculated cases for missing and
   conflicting states, zero denominators, duplicate rejection, time boundaries,
   filtering, unequal observation counts and baseline eligibility. Legacy output
   is not the acceptance target where its calculation contains a confirmed error.
4. **Compare local reports.** Run an approved local comparison with representative
   exports. Reconcile material differences before replacing the working tool.
5. **Approve the intended workflow.** Confirm report review, storage/sharing,
   decision uses and version-change acceptance. Regression checks alone do not
   establish clinical validation.

## Deferred capabilities

| Capability | Dependency |
| --- | --- |
| Measured or interval-based sleep duration | Verified start/end semantics, overlaps and elapsed-time rules |
| Expected-check coverage and missed checks | Actual schedules and admission/discharge/leave eligibility |
| Clinical alerts, prediction or causal interpretation | Defined use case, appropriate study design and clinical validation |
| Direct connections and scheduled reports | Chosen local integration and operational access model |
| Encrypted exports or hosted multi-user use | Defined deployment, identity and data-protection approach |

Recorded-field completeness is implemented; schedule coverage is not. Fully
populated received rows can still omit checks never supplied. Baseline count and
completeness settings are software defaults, not clinically established thresholds.
Admission-weighted and observation-weighted unit results answer different questions
and remain separately labelled.

Keep local adaptation outside shared calculations. Changes to observation semantics
or formulas need a documented reason, synthetic expected results and a version
change. Prioritize a verified local import and report comparison before adding
analytical complexity.
