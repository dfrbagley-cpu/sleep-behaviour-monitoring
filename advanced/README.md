# Advanced research edition

This separate entry point builds demographic cohort summaries and a retrospective next-day baseline evaluation. It uses the same normalization and sleep/awake-behaviour definitions as the hospital edition. It does not alter the hospital reporting command.

No clinical future forecasts, risk scores, demographic prediction model or treatment recommendations are enabled. This first slice establishes input quality, honest baselines and reproducible evaluation before more complex modelling.

## Run

Only base R is needed for CSV input, CSV exports and the self-contained HTML report. No network services or package installation occur during a run.

```sh
Rscript --vanilla advanced/run.R --demo --output outputs/research-demo
Rscript --vanilla advanced/run.R --config config/site.example.dcf --input /approved/observations.csv --demographics /approved/demographics.csv --output /approved/research-results
Rscript --vanilla tests/test_advanced.R
```

Output must be an empty or new directory. XLSX observations use the shared optional `readxl` dependency; demographic input is CSV. Settings and column mappings for observations remain in the normal site config. Its `StartDate` and `EndDate` determine the report period. A report needs at least 14 calendar dates. `BaselineStart` and `BaselineEnd`, if supplied, make earlier normalized observations available for historical evaluation.

The separate `advanced/research-policy.dcf` declares evaluation rules before any outcomes are evaluated. Pass `--policy FILE` to supply an institution-reviewed policy. The current implementation fixes `HoldoutDays: 14` and `TrailingCalendarDays: 7`; minimum history days, known observations, recorded completeness and group contributors are explicit. Default group suppression is below five distinct contributing patients; the reader does not permit a threshold below three. Do not lower thresholds to make weak results appear usable.

## Demographics input

Use exactly these five columns and one row for each patient/episode combination:

```csv
patient_id,episode_id,age_at_admission,sex_recorded,diagnostic_group
LOCAL-P001,LOCAL-E001,78,Female,Locally approved diagnostic group
LOCAL-P002,LOCAL-E003,,,
```

- Identifiers must match the observation export. A returning person can have a different age and diagnostic group on another episode.
- Use age in completed years at admission, between 0 and 120. Leave it blank if unknown. Dates of birth and extra columns are rejected.
- Blank sex or diagnostic group becomes `Unknown`. Recorded sex is not inferred from names or another field. Diagnostic groups are institution-defined; no coding-system interpretation is imposed.
- Duplicate keys, missing keys and invalid nonblank ages stop the run. Duplicate rows are rejected even if unused in the selected observations.
- Missing demographic matches preserve every observation in Unknown groups. Extra demographic rows are counted as unused. The join uses `match()` and cannot multiply or reorder observations.

The demo writes fictional observations and matching demographics for the eight existing demo participants. Demographics were assigned for software demonstration, independently of the observation generator. They provide no evidence of demographic effects.

## What the cohort report means

Age bands are Under 65, 65–74, 75–84, 85 and over, and Unknown. Separate tables group by age band, recorded sex and diagnostic group, for the selected population and by unit. This is stratification, not case-mix adjustment.

Rates pool known observations. Sleep means asleep observations divided by known sleep observations. Behaviour means yes observations divided by known behaviour observations among confirmed-awake observations. Repeated observations can weight one person more heavily. These are not measured hours, event probabilities, person-weighted comparisons, causal effects or significance tests.

Every cell reports distinct group patients, contributing patients and contributing episodes. Rates and observation denominators are suppressed when too few distinct patients contribute known outcome observations. Multiple admissions by one person do not increase the patient threshold. Small counts remain visible. These local outputs are **not anonymized**: labels, counts and overlapping groups can still reveal information. Do not publish real inputs, output folders or research reports to GitHub.

## Backtest design

The holdout consists of the last 14 calendar dates ending at the configured `EndDate`. It is not moved to the final available observation. For each outcome, both methods use exactly the same eligible patient/episode/unit/target-date rows:

1. **Last observed day:** the immediately preceding calendar day's eligible recorded percentage. A stale observation before a gap cannot substitute for yesterday.
2. **Trailing seven-day mean:** an equal-day mean of eligible dates in the seven calendar days strictly before the target, with at least three available days by default.

Both require an eligible immediately preceding day. Daily history and target observations must meet the declared minimum known count and recorded completeness. Unknown values do not become zero. Missing dates are never inserted as measured targets. History cannot cross patient, episode or unit boundaries. A unit transfer can leave a partial day; completeness among recorded observations cannot detect all such schedule limitations.

This is rolling-origin, past-only evaluation: earlier holdout outcomes may become history for a later holdout target once that day has ended. Neither baseline has fitted parameters. Target-day and later values cannot enter that target's predictions. There is no random record split, interpolation across gaps, or look-ahead normalization.

MAE is the mean absolute percentage-point difference between the recorded outcome and the historical prediction, with equal weight per eligible target. The comparison uses paired targets; target counts cannot differ between methods for the same outcome. Outcome eligibility can differ between sleep and behaviour. Summary errors are suppressed for too few distinct patients. The report shows observed holdout rows excluded by each eligibility rule. It cannot report missing occupied bed-days without a census and expected observation schedule.

Errors are descriptive: repeated person-days are dependent, there are no uncertainty intervals or significance claims, and this holdout is insufficient to establish generalization to new patients or another ward. No method is automatically selected or deployed. Demographics are not prediction features in this version.

## Files generated

- `research-report.html`: complete local report with no external assets or scripts.
- `demographic-cohorts.csv`, `demographic-join-audit.csv`: suppressed descriptive metrics and join coverage.
- `backtest-summary.csv`, `backtest-coverage.csv`, `research-readiness.csv`: paired baseline errors, exclusions and predeclared settings.
- `data-quality-summary.csv`: counts of shared normalization and detailed-behaviour issues.
- `research-receipt.dcf`, `source-manifest.csv`: config, policy, input and analysis-code checksums plus R version. Checksums support reproduction, not cryptographic signing.
- Demo only: `synthetic-observations.csv` and `synthetic-demographics.csv`.

Individual paired backtest rows exist internally for testing but are not exported. Real input observations and individual demographics are not copied to the output folder. CSV text is escaped against spreadsheet formulas, and HTML labels are escaped.

## Next development gates

1. Define one useful decision and its outcome with the intended clinical or operational owner. Do not equate improved prediction error with improved care.
2. Add expected observation schedules, occupancy/exposure, recording-policy changes and data-availability timestamps. Audit missingness and measurement differences before adding a model.
3. Agree clinically meaningful groups and the time at which every candidate input is available. Diagnostic labels finalized later in an admission cannot be used in an earlier prediction.
4. Obtain an appropriate representative development sample. Predeclare patient-separated and temporal evaluation, comparison baselines, uncertainty and minimum acceptable performance, plus subgroup checks.
5. Consider demographic and clinical predictors only when they improve an agreed outcome on valid held-out data. Evaluate calibration for any probabilistic model and audit group differences; stratified averages do not establish fairness.
6. Evaluate prospectively in a silent, reviewed workflow before considering actionable forecasts or deployment in patient care.

The command remains a local research workbench. A more polished interface and complex models should follow evidence that the proposed prediction changes a worthwhile decision.
