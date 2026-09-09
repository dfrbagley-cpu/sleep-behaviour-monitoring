# Contributing

Reproducible bug reports, documentation corrections and feedback on the report
workflow are welcome. [Reuse licensing is pending](LICENSING.md); this document
does not add licence terms or a contribution agreement. Discuss code contributions
with the maintainer before preparing a substantial change.

## Report a problem

Open an [issue](https://github.com/dfrbagley-cpu/sleep-behaviour-monitoring/issues)
with:

- The edition, release version, R version and operating system.
- The command or steps used, the expected result and the actual result.
- A small **fully synthetic** input and sanitized example configuration that
  reproduce the problem. Include error text with local identities and paths removed.

Never upload patient records, identifiable screenshots, internal configurations,
credentials or real generated reports. Replacing a name alone does not make a
real clinical record an appropriate public example. For sensitive findings, see
[SECURITY.md](SECURITY.md).

## Develop locally

Keep changes focused. Calculation changes need a documented metric definition and
a synthetic case with an independently calculated expected result. Avoid creating
a second set of formulas for the hospital edition. Run relevant checks from the
repository root:

```sh
Rscript --vanilla tests/run_tests.R
Rscript --vanilla tests/test_editions.R
Rscript --vanilla tests/test_advanced.R
Rscript --vanilla tests/test_import.R
python tests/test_release.py
```

`openxlsx` enables workbook checks; install optional packages with
`Rscript --vanilla scripts/install_optional.R`. Review the generated report when
changing its layout. Do not commit `outputs/`, local inputs or local settings.

For changes to prediction or statistical methods, describe the intended question,
assumptions, evaluation population and a useful baseline before adding complexity.
Synthetic success alone does not support a claim of clinical or predictive value.
