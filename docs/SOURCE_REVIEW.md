# Source review and migration decisions

This record comes from static inspection of the supplied legacy R script.
The original was not executed. No real observations were supplied or validated.
Credentials, personal contact information, internal locations and organization labels
are intentionally excluded from this record and the public implementation.

## Confirmed calculation and selection issues

| Issue | Legacy calculation or behaviour | Intended correction and expected output change |
| --- | --- | --- |
| Inconsistent behaviour rate | Total, morning, evening and night use `all YES rows / awake rows`. Afternoon limits the numerator to the primary awake field, but its denominator also includes fallback awake rows. | Normalize sleep state once and apply the same awake restriction to numerator and denominator in every period. Non-awake behaviour rows no longer inflate the rate; valid fallback awake rows contribute consistently. |
| Missing behaviour values | Every awake row contributes to the denominator, including rows without a documented behaviour status. | Distinguish documented absence from unknown status. Report `awake YES / awake known behaviour status`, plus missing-status counts. The rate may rise when missing values previously behaved as absence. |
| Sleep duration overstatement | `asleep rows / (awake rows + asleep rows) * 24`, or the corresponding fixed period length. | Default to the proportion of classified observations recorded asleep. Do not present inferred clock hours as measured sleep duration. Any later interval-based duration requires a verified recording model and coverage checks. |
| Observation weighting | Department results pool rows across people and days. | Label the current aggregate as observation-weighted. An equal-person or equal-day mean is a separate metric, requiring an explicit policy. Dense charting must not silently become greater clinical importance. |
| Patient and department mismatch | Individual summaries filter by patient name across the entire input, while the department summary filters department. | Apply department and date scope before both aggregations. Results change for people with observations in multiple departments. |
| Limited patient handling | Four patient slots are configured; only three have calculations and appear in the combined output. | Use a variable-length patient selection and grouped calculations. Every valid selected person receives a summary. |
| Incorrect raw selection | `PAT_NAME == c(patient1, patient2, patient3)` compares against recycled positions. | Use membership matching within the same scope as the summaries. Selected rows no longer depend on their position in the input. |
| Name-based identity | Display names are the only patient key. | Require a stable local identifier, using a synthetic identifier in examples. People sharing a name must remain separate. |
| No date enforcement | Report date and maximum report-size text appear in metadata; no observation-date filter or duration limit is applied. | Validate timestamps and enforce an explicit reporting window. Out-of-window rows are excluded or rejected according to the documented import policy. |
| Brittle missingness | Fallback classification activates only when the primary value equals one space. | Normalize whitespace, empty strings and actual missing values before classification. Unknown primary values must not silently become known states. |
| Conflicting fallback flags | A blank primary value with both awake and asleep fallback flags is counted in both categories. | Classify conflicts as unresolved and report them. One observation must contribute to at most one sleep state. |
| NA-index row counting | Some `dat[logical_condition, ]` filters can contain `NA`; the resulting placeholder rows are included by `nrow`. | Use explicit nonmissing predicates or validated normalized fields. Missing inputs cannot create additional counted observations. |
| Time parsing assumptions | Character values are compared lexically with strings such as `06:00`. | Parse validated timestamps and derive local time. Reject malformed values; define time zone and daylight-saving behaviour. |
| Zero denominators | Divisions can produce `NaN` or infinity. Later blank replacement is partial and occurs after percentage formatting. | Return an explicit unavailable value with numerator and denominator counts. A lack of eligible observations is not zero prevalence. |
| Inconsistent quality scope | Error counts use the full input, even when the analysis selects one department. Counts only recognize the single-space missing convention. | Produce quality counts for the analysed scope and explicit exclusions. Report missing, unknown and conflicting states separately. |

## Output security, portability and maintenance

- An input-workbook credential is embedded in the script. Remove credentials from
  distributable code and examples. If still valid, replace it through the normal
  credential-management process; do not reproduce it in release history.
- The output workbook is saved without encryption. The workbook-protection call
  is commented out; workbook structure protection would not establish encryption.
  Documentation must say exactly what each export protects.
- Raw selected observations are automatically copied into the workbook. The public
  demo uses synthetic data only; identifiable local exports require an explicit
  operator choice and a controlled destination.
- Person names are used in worksheet and output names. This discloses identity in
  filenames and can fail on invalid worksheet characters or excessive lengths.
  Use neutral report names and validated worksheet names.
- Saving uses overwrite mode. A later run can replace an earlier report without
  preserving its provenance. Use explicit overwrite behaviour and run metadata.
- `rm(list=ls())`, `setwd()` and `attach()` modify the user's R session. Explicit
  function arguments and local data references avoid destructive state changes
  and column-name collisions.
- Environment-specific drive paths and a spreadsheet automation dependency limit
  portability. Configuration and standard local file readers should replace them;
  encrypted workbook support must be treated as a separate, documented capability.
- Repeated hand-written patient and time-period blocks caused observable drift.
  One tested normalization and aggregation path should serve every selected group.

## Assumptions that remain unresolved

1. **Recording model:** Does each row represent a point observation, a fixed period,
   or a retrospective interval? A point observation does not establish sleep until
   the next recorded time. Do not infer duration until this is resolved.
2. **Expected schedule:** What cadence applies to each person and date, and what
   changes during admission, discharge, leave or intensified observation? Without
   this information, an overall expected-observation coverage percentage is not
   established. A gap count alone is not coverage.
3. **Behaviour meaning:** Does blank mean missing, absent or not applicable? Does
   the summary flag reliably represent all behaviour categories? Confirm locally;
   the list of behaviour labels in the script is descriptive, not its derivation.
4. **Conflicting states:** Decide how primary and legacy fallback values are
   reconciled. Preserve conflict counts and document any precedence rule.
5. **Time boundaries:** Confirm time zone, period definitions and whether overnight
   observations belong to the calendar day or the preceding evening's report day.
6. **Clinical interpretation:** Descriptive changes cannot establish a medication
   effect, a cause of behaviour, over-sedation or staffing need. Those applications
   require local clinical review, context and validation of intended use.

## Release acceptance implications

The legacy workbook is useful for understanding workflow and terminology; it is
not a universal numerical acceptance target because confirmed errors need to change.
Use synthetic cases with independently calculated expectations for patient scope,
period boundaries, missing/conflicting states, behaviour eligibility and empty groups.
Compare representative local reports before replacing the working tool, explaining
each changed result. Do not claim clinical validation from software tests alone.
