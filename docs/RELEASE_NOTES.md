# Public development preview — 0.4.0

Two editions now share the same calculation engine:

- **Hospital:** a copyable R package with RStudio Source support, Windows launcher,
  offline setup check, four-sheet Excel workbook and generated charts.
- **Advanced development:** demographic strata and retrospective comparisons of
  two next-day forecast baselines, using past observations only.

This release also adds an explicit local export adapter, synthetic examples,
an engineering case study and regression checks on Linux and Windows.

## Downloads

| File | Purpose |
| --- | --- |
| Hospital ZIP | Extract completely; start with START_HERE.md, check_setup.R and run_hospital.R |
| Advanced-Development ZIP | Complete source for both editions; run the synthetic research command in README.md |
| Synthetic-Demos ZIP | Both complete generated reports with their supporting CSVs and fictional input data |
| Synthetic-Workbook XLSX | Inspect the four-sheet clinical-review layout without installing R |
| SHA256SUMS.txt | Checksums of these downloads |

The packages do not install R or dependencies. Hospital Excel output needs
`openxlsx`; Excel input needs `readxl`. After approved setup, report generation
runs locally without network access.

Demographic results are descriptive strata, not case-mix adjustment. Forecast
results evaluate simple historical baselines on synthetic or explicitly supplied
local records; prospective clinical scores remain disabled. Experimental
significance testing is blocked in the hospital runner.

The software is ready for local acceptance testing, not presented as clinically
validated. Verify source mappings and observation meanings before replacing an
existing report. Password-protected workbook import still requires a separately
approved local conversion step. Reuse licensing remains pending; public source
visibility does not establish an open-source licence. See LICENSING.md.

Release assets are published only after both operating-system verification jobs
succeed. Existing published versions are not overwritten.
