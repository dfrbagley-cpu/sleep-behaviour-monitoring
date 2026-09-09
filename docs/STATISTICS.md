# Daily comparisons and experimental statistics

The default report shows observed changes and the amount of data behind them.
**Automatic statistical testing is disabled by default.** Short time-series
simulations found materially more false flags than the nominal 5% rate with the
experimental method below. Its sample-size and data-quality gates do not fix
that limitation. Holm adjustment does not repair invalid individual p-values.

Use the descriptive reports for reviewing recorded patterns. The experimental
option is for statistical development and local model assessment; it is not a
validated basis for clinical decisions. A small p-value does not establish a
clinical benefit, harm, medication effect, oversedation, or the reason a pattern
changed. An unflagged result does not establish equivalence or absence of change.
The [American Statistical Association statement](https://www.tandfonline.com/doi/full/10.1080/00031305.2016.1154108)
explains why p-values must be interpreted alongside effect size, assumptions,
measurement quality and context.

## Values available by default

- Current and baseline mean daily percentages, giving each available day equal
  weight. A change is the current mean minus the baseline mean, in percentage
  points. These means can differ from pooled check percentages elsewhere in the
  dashboard, where days with more checks have greater weight.
- The number of days with a finite daily rate in each period. These are available
  days, not a claim that every day passed the quality criteria.
- An explicit reason when experimental inference is unavailable. P-values,
  uncertainty intervals and the experimental flag remain missing when not tested.

Sleep uses known sleep checks as its denominator. Behaviour metrics use
confirmed-awake checks with the relevant behaviour field known. Unknown does not
mean absent. A point-check proportion is not measured duration or an episode count.
Field completeness is the fraction of relevant recorded checks with that field
known; it cannot reveal observations that should have happened but were never
recorded.

## Experimental algorithm

The public function is `compute_monitoring_statistics(metric_daily, config)`.
Testing requires explicit `statistics_enabled = TRUE` in its configuration;
omitting that setting leaves it disabled. The deterministic low-level
`sbm_hac_contrast(baseline, report, lag = 7, alpha = 0.05)` is a development helper.
It does not check calendar dates or obtain clinical approval.

For each patient, episode, unit and metric present in the current period, the
method fits the daily percentage to an intercept and a current-period indicator.
The current coefficient is the difference in mean daily percentages. The
Newey-West covariance uses the Bartlett kernel, the configured daily lag, no
prewhitening, and the finite-sample multiplier `n/(n - 2)`. The reference
distribution is the standard normal distribution. This corresponds to the
unprewhitened formulation described in the
[sandwich methodology paper](https://www.jstatsoft.org/v11/i10/) and
[Newey-West function documentation](https://search.r-project.org/CRAN/refmans/sandwich/html/NeweyWest.html).

The interval is a nominal pointwise `(1 - alpha)` interval: 95% with the default
alpha. It is not adjusted for multiple comparisons, and its actual finite-sample
coverage is not established. A pointwise interval can exclude zero while a
Holm-adjusted p-value does not cross the selected threshold.

Raw p-values are adjusted with Holm across the full family of planned
patient/episode/unit/metric contrasts in the generated report, including those
that could not be tested. This prevents a display filter from silently reducing
the comparison family. Holm can control family-wise error under dependent tests
when the individual p-values are valid; that prerequisite is not established for
this experimental implementation. See the
[official R adjustment documentation](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/p.adjust.html).
Repeatedly trying new date windows is outside that family and is not corrected.

The output statuses are `Experimental adjusted-p flag` and
`No experimental adjusted-p flag`. The internal `significant` field is only that
experimental adjusted-p threshold indicator. It must not be presented as proof of
statistical or clinical significance. It is `NA` for untested rows.

## Eligibility gates

The engineering defaults are `min_stat_days = 28`,
`min_stat_known_per_day = 6`, `min_completeness_pct = 80`, `hac_lag = 7`, and
`alpha = 0.05`. They are configurable and have not been clinically validated.

Testing requires complete adjacent baseline and current date windows, each at
least the configured minimum length. Every day must have a finite rate, enough
known eligible checks, and adequate field completeness. Both periods must have
day-to-day variation, and the estimated contrast variance must be positive.
Missing dates, zero variation, missing baseline matches and failed quality checks
produce an explicit untested result. The comparison uses the same patient,
episode and unit; it does not silently pool previous admissions or different wards.

The daily series is never compressed to hide missing dates. The
[Federal Reserve's research on HAC with missing observations](https://www.federalreserve.gov/pubs/ifdp/2012/1060/ifdp1060.htm)
shows that missing observations require special handling. This implementation
suppresses testing for incomplete or nonadjacent windows instead.

HAC is asymptotic. Its assumptions include sufficiently long series, appropriate
short-range dependence, stable measurement and observation processes, and a
suitable model within each period. These checks do not establish those
assumptions. Trends, persistent behaviours, observation-frequency changes,
informative missingness and changes in care can undermine inference. More point
checks in the same day do not substitute for additional days.

## Reproducible null stress check

This small development check tested whether the implementation showed gross
anti-conservatism; it did. It is not clinical validation or a comprehensive
calibration study. It generated stationary Gaussian daily series with no change
in mean, split each into two adjacent 28-day periods, and used lag 7 and a raw
two-sided 0.05 threshold. Gaussian values were passed directly to the helper to
test its reference distribution; they were not presented as patient percentages.

With seed `20260907` and 500 replicates per scenario, the results were:

| AR(1) coefficient | False flags | Replicates | Observed false-flag fraction |
| --- | ---: | ---: | ---: |
| 0.0, independent days | 45 | 500 | 9.0% |
| 0.3 | 70 | 500 | 14.0% |
| 0.6 | 88 | 500 | 17.6% |
| 0.8 | 172 | 500 | 34.4% |

Monte Carlo estimates vary with the seed and simulation environment. The size of
these departures is sufficient to reject a claim that the current default gates
yield reliable nominal p-values. Testing therefore remains off by default.
Because a one-contrast report has no multiplicity reduction, Holm cannot be used
to dismiss this finding.

Run from the repository root in R:

```r
source("R/statistics.R")
set.seed(20260907)
for (phi in c(0, 0.3, 0.6, 0.8)) {
  p <- replicate(500, {
    y <- if (phi == 0) rnorm(56) else
      as.numeric(arima.sim(list(ar = phi), n = 56))
    sbm_hac_contrast(y[1:28], y[29:56], lag = 7)$p_value
  })
  print(c(phi = phi, flagged = sum(p < 0.05),
          replicates = length(p), false_flag_fraction = mean(p < 0.05)))
}
```

Before enabling any inferential method for operational interpretation, evaluate
it against the intended observation process, plausible serial dependence and
missingness, and the actual lengths and distributions of the series. A suitable
replacement may require a different model, uncertainty procedure or data design.
Changing a threshold until the demo appears convincing is not validation.

## Ward benchmarks

Ward comparisons are descriptive. They exclude the index patient across all
episodes, use the selected current dates and ward, and average eligible peer admission rates
with equal admission weighting. A person with several admissions can contribute
several rates; the entire index person remains excluded. Patient mix, observation practices and care needs
can differ. Ward comparisons have no p-value or statistical-significance label.

## Output contract

`compute_monitoring_statistics()` returns one row per planned current contrast:

`patient_id`, `episode_id`, `unit`, `metric`, `baseline_mean_pct`,
`report_mean_pct`, `effect_pp`, `ci_low_pp`, `ci_high_pp`, `standard_error_pp`,
`p_value`, `p_adjusted`, `n_baseline_days`, `n_report_days`, `eligible`,
`significant`, `status`, `method`, `hac_lag`, `family_size`.

`eligible` means that a requested experimental computation passed its mechanical
gates. It does not mean the statistical model was validated. `family_size` is the
number of planned current contrasts. Undefined numerical outputs remain `NA`.
