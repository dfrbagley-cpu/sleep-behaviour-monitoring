# Configuration and input guide

Run the demo first, then copy `config/site.example.dcf` to a folder outside the
repository. Edit that copy in a text editor. DCF uses one `Field: value` per line;
keep one record without blank lines between settings. Unknown field names are
rejected. Configuration contains settings, not executable R code.

```sh
Rscript --vanilla run.R --config "/local/site.dcf" --input "/local/observations.csv" --output "/local/reports/run-001"
```

Use actual paths and an empty output directory for each run. Existing reports are
not overwritten. Reports contain supplied identifiers and are not encrypted by
this tool. Keep local inputs, settings and reports outside the repository.

## Input columns

Each configuration field names the actual source header. Mappings must be distinct.
Identifiers are read as text, preserving leading zeroes.

| Canonical field | Configuration field | Meaning |
| --- | --- | --- |
| `observation_id` | `ObservationIdColumn` | Unique, nonblank observation ID |
| `patient_id` | `PatientIdColumn` | Stable person ID; a name is not an identity key |
| `episode_id` | `EpisodeIdColumn` | Stable admission/episode ID |
| `unit` | `UnitColumn` | Unit attached to this observation |
| `observed_at` | `TimestampColumn` | ISO timestamp with seconds and an explicit offset |
| `sleep_state` | `SleepStateColumn` | Recorded sleep state; values can be missing |
| `behaviour` | `BehaviourColumn` | Recorded presence/absence; blank is unknown |

All seven columns must exist. Identifier and timestamp values must be populated.
Repeated observation IDs or patient/admission/timestamp combinations stop the import;
reconcile duplicates at source. Structural validation precedes date/unit selection.

Accepted examples are `2026-08-08T14:30:00-04:00`, `2026-08-08T14:30:00-0400` and
`2026-08-08T18:30:00Z`: all represent the same instant. Fractional seconds, timezone-free
timestamps, separate date/time columns and native Excel dates are not auto-converted.
Prepare an explicit timestamp in the local adapter; do not guess the offset for an
ambiguous daylight-saving time.

CSV needs no packages. XLSX reads the first worksheet and requires `readxl`, installed
with `Rscript --vanilla scripts/install_optional.R`. XLSX must be unencrypted. Handle
encrypted exports through the approved local workflow before import; there is no
password configuration field.

## Report settings

| Field | Setting |
| --- | --- |
| `Title` | Required report title |
| `Timezone` | Required IANA zone such as `America/Toronto`, or `UTC`; timestamps are converted to it |
| `StartDate`, `EndDate` | Required inclusive report dates, `YYYY-MM-DD` |
| `BaselineStart`, `BaselineEnd` | Optional pair; baseline must end before the report starts |
| `ReportingDayStart` | `HH:MM`, default `00:00`; earlier local times belong to the preceding report date |
| `TimeBands` | Required `Name=HH:MM-HH:MM` entries separated by `|`; cover every clock minute exactly once |
| `Units`, `Patients` | Optional exact selections separated by `|`; omit to include all within dates |
| `MinBaselineObservations` | Default `10`; minimum known observations in **both** baseline and report for a change calculation |
| `MinCompletenessPct` | Default `80`; minimum recorded-field completeness in **both** periods for that metric |
| `EstimateHours` | Default `false`; `true` adds a standardized projection, not measured sleep duration |

Example bands:

```text
TimeBands: Morning=06:00-12:00|Afternoon=12:00-18:00|Evening=18:00-22:00|Night=22:00-06:00
```

Starts are inclusive; ends are exclusive. `24:00` is allowed as an end boundary.
Up to 12 unique names are supported; `Total` is reserved. Bands follow local clock
time even when the reporting-day start changes. With `ReportingDayStart: 06:00`,
a 02:00 check on August 9 belongs to report date August 8 and the Night band.

Baseline matches patient, admission, unit and band. Sleep eligibility uses the known
sleep count; behaviour uses confirmed-awake rows with known behaviour status. Failed
thresholds suppress the change, with a reason; they do not erase proportions. These
thresholds are software defaults, not clinically validated cutoffs.

## Codes and fallback fields

| Field | Default |
| --- | --- |
| `AwakeCodes` | `Awake` |
| `AsleepCodes` | `Asleep` |
| `BehaviourYesCodes` | `YES` |
| `BehaviourNoCodes` | `NO` |
| `AwakeCalmColumn` | Optional source column; remove the example setting if unused |
| `SleepingColumn` | Optional source column; remove the example setting if unused |
| `AwakeCalmCodes` | `Awake/Calm` |
| `SleepingCodes` | `Sleeping` |

Separate alternative codes with `|`. Matching ignores case and outer whitespace.
Awake/asleep sets must not overlap; neither may behaviour yes/no sets. Empty strings
cannot be configured as a no-behaviour code. Unmapped codes become unknown with a
quality issue; inspect issues before interpreting results.

Recognized fallback flags can classify sleep when its primary value is blank.
Conflicting sleep evidence is unknown and reported. An awake/calm flag does **not**
fill missing behaviour. Confirm whether local blank behaviour means absent or
undocumented before designing an adapter; that meaning remains unresolved. A
configured optional fallback column must exist in the input.

## Metric definitions

| Metric | Calculation |
| --- | --- |
| Sleep percentage | Asleep / (awake + asleep) observations |
| Behaviour percentage | Awake with behaviour yes / awake with behaviour yes or no |
| Sleep-field completeness | Known sleep / all received observations |
| Awake behaviour-field completeness | Awake with known behaviour / all confirmed-awake observations |
| Baseline change | Report percentage minus baseline percentage, in percentage points |
| Pooled unit result | Metric calculated over selected unit observations |
| Equal-admission unit result | Mean of available patient/admission percentages in that unit |

Zero denominators are unavailable, never inferred zero. Equal-admission means
exclude unavailable values and show contributing-admission counts. A person with
multiple admissions can contribute multiple summaries. Recorded-field completeness
does not establish expected-check coverage; schedules and eligibility windows are
not yet implemented.

## Troubleshooting

- **No observations match:** check dates, reporting-day start and exact unit/patient
  selections. Baseline rows alone cannot create a current report.
- **Required column missing:** use the exact header; remove unused optional fallback
  mappings copied from the example.
- **Invalid timestamp or duplicate:** resolve the reported source-row numbers; the
  tool will not guess or silently remove records.
- **Output is not empty:** choose a new run folder.
- **Excel package unavailable:** run the optional installer once. HTML and CSV remain
  available without those packages.
