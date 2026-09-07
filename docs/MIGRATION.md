# Integrating the original R tool

This repository is a documentation foundation. The original R source has not
been imported, and the analytical behaviour below is an integration plan, not a
description of implemented or clinically validated features.

## Ordered integration steps

1. **Inventory the source.** Identify application entry points, packages, input
   files, calculations, exports, local paths, and environment-specific text.
   Record the current outputs and their assumptions before changing formulas.
2. **Prepare a synthetic import.** Remove institutional branding, real records,
   identifiers, screenshots, credentials, and local infrastructure details from
   material intended for this public repository. Build deterministic synthetic
   fixtures that exercise the existing calculations without copying patient data.
3. **Resolve the observation contract.** It is currently unresolved whether a
   record describes a point-in-time check, an explicit interval, or a mixture.
   Document this from the source and recording workflow before calculating sleep
   duration. Define timestamps, timezone, record identity, state codes, unknown
   values, observation schedules, admission windows, and unit transfers.
4. **Capture synthetic parity cases.** Run known synthetic inputs through the
   original calculations and preserve expected outputs. Review discrepancies:
   documented corrections may intentionally replace incorrect legacy behaviour.
5. **Extract shared calculations.** Separate pure R transformation and summary
   functions from the user interface, import adapters, and configuration. Keep
   original source rows traceable through validation and aggregation.
6. **Add a single documented configuration example.** Provide fictional labels
   and mappings, then validate settings before processing. Reject unknown codes
   and invalid settings with actionable messages rather than guessing.
7. **Implement and verify descriptive summaries.** Show observation coverage,
   the selected baseline, and the denominator for each measure. Keep patient
   comparisons and unit summaries explicitly defined and separately labelled.
8. **Connect and package the interface.** Integrate verified functions into the
   existing app, document dependency installation and a synthetic launch path,
   and check that a fresh environment can reproduce the example outputs.

## Configuration and shared calculations

| Configuration or input adapter | Shared, versioned calculation rules |
| --- | --- |
| Display labels, site/unit names, input column mappings | Validation, duplicate/conflict handling, and provenance |
| Mapping local codes to documented canonical states | Meaning of canonical states; unknown is distinct from absence |
| Timezone, reporting-day start, day/night bands | Timestamp parsing, elapsed-time arithmetic, boundary splitting |
| Patient observation schedules and eligibility windows | Expected-check generation and coverage denominators |
| Explicit baseline window and comparison eligibility settings | Baseline exclusion rules and comparison calculations |
| Local file locations and output destinations | Aggregation formulas and export field definitions |

Configuration must not silently redefine the meaning of a metric. Any change to
observation semantics or a formula requires documentation, versioning, and tests.
Do not average ordinal behaviour codes as if their numerical distances had an
established meaning without an explicitly justified measurement model.

## Analytical boundaries

- For point checks, describe the share of recorded checks in each state. Do not
  infer duration by multiplying counts by cadence or carrying states across gaps.
- For explicit intervals, use recorded duration and handle overlaps and boundaries
  deterministically. Keep uncovered time visible; it is not awake time.
- Calculate expected observations only where an applicable schedule and patient
  eligibility window are known. Otherwise report that coverage is unavailable.
- Fix the baseline to a visible, explicitly selected earlier period within the
  relevant admission. Exclude the comparison period and show both periods' valid
  observations and coverage. Suppress comparisons with insufficient information.
- Distinguish an equal-weight patient summary from a pooled observation or
  recorded-time summary. Label the chosen denominator and contributing patients.
- Describe time-of-day patterns and changes from baseline. Sleep observations
  alone do not establish over-sedation, medication effects, behavioural triggers,
  or a diagnosis. Predictive and causal claims require separate validation.

## Minimum synthetic test matrix

| Case | Required result |
| --- | --- |
| Eight expected checks: two asleep, two awake, four missing | 50% asleep among recorded checks; 50% coverage; no invented sleep hours |
| Explicit intervals: 15 minutes asleep, 60 awake | 20% of recorded time asleep; distinct from point-check calculations |
| All observations missing | Summary unavailable; missingness retained, never converted to zero |
| Observation cadence changes during an admission | Expected checks follow the applicable schedule; no double counting |
| Duplicate, conflicting, overlapping, or invalid records | Deterministic rejection or visible conflict; no silent inflation |
| Admission, discharge, or transfer within a period | Eligibility and unit attribution respect the actual boundaries |
| Midnight, reporting-day boundary, daylight-saving transition | No lost or duplicated elapsed time; correct reporting-date assignment |
| Comparison-period values change | Fixed baseline remains unchanged; no current-period or future leakage |
| Patients have unequal coverage or observation frequency | Equal-patient and pooled summaries remain distinct and correctly labelled |
| Synthetic input with known original output | Parity, or a documented correction with revised expected output |

## Primary references

- [CDC: Describing epidemiologic data](https://www.cdc.gov/field-epi-manual/php/chapters/describing-epi-data.html)
  explains why comparisons need denominators consistent with the observed population.
- [NIST: Autocorrelation](https://www.itl.nist.gov/div898/handbook/eda/section3/eda35c.htm)
  describes temporal dependence and the equal-spacing assumption of ordinary
  autocorrelation. Simple independent-observation tests should not be added by default.
- [NICE NG10, recommendation 1.4.45](https://www.nice.org.uk/guidance/ng10/chapter/Recommendations)
  requires consciousness and physiological monitoring following rapid
  tranquillisation. This supports the design boundary that recorded sleep is not
  a stand-alone assessment of sedation; it is not a local treatment protocol.
