# Hospital edition — 0.4.0

This is a portable R reporting package for a hospital shared drive. It creates the
Excel workbook and charts directly. It is ready for a local acceptance trial;
compatibility with your current export and hospital computer has not been verified.

## First run

1. Extract the **entire ZIP** to an approved shared-drive folder. Do not run files
   from inside the ZIP. R runs on your computer; the shared drive stores files.
2. Open `check_setup.R` in RStudio and click **Source**. The hospital edition needs
   R, `openxlsx`, and PNG chart support. Excel input additionally needs `readxl`.
   Have IT preinstall approved packages and their dependencies. The check and
   reporting scripts do not download or install anything.
3. Open `run_hospital.R` in RStudio and click **Source**. The initial settings use
   fictional data. The console prints the new output folder and Excel report path.
   If Rscript is on PATH, you can instead double-click `RUN_HOSPITAL.cmd`.
4. Open `monitoring-report.xlsx`. Check all four sheets and the combined chart.

On computers with Rscript outside PATH, IT can set `SBM_RSCRIPT` to its full
executable path. The RStudio route works without that setting. `RUN_HOSPITAL.cmd`
uses `pushd` to support UNC shares. Windows execution has not been tested in this
build environment; use the synthetic run to confirm it on your workstation.

## Run your own export

Edit `config/hospital.example.dcf` for your report and baseline dates, actual column
headers, unit/patient selections and optional individual behaviour mappings.
The supplied dates are demonstration dates, not a rolling reporting window.
Use `hospital/EXPORT_MAPPING.md` and `docs/CONFIGURATION.md` when mapping headers.
For separate date and time columns, `docs/IMPORT_ADAPTER.md` provides an explicit
local conversion command and a matching report configuration.

Then edit `hospital/settings.R`:

```r
hospital_settings <- list(
  mode = "local",
  input_file = "X:/Monitoring/input/observations.xlsx",
  config_file = "X:/Monitoring/settings/site.dcf",
  output_parent = "X:/Monitoring/reports"
)
```

The paths above are examples. Save your edited configuration at `config_file` or
use `config/hospital.example.dcf` there. Forward slashes work for Windows paths.
Run `run_hospital.R` again. Each run creates a new folder; earlier reports are kept.
Keep settings outside the extracted software when you want to carry them forward
to a later release. Do not put live hospital files in a Git checkout.

## What you receive

| Output | Use |
| --- | --- |
| Dashboard | Focus person's summary, sleep and behaviour on one timeline, descriptive daily changes and data availability |
| Expanded analytics | Individual behaviours, own-history comparisons, descriptive ward comparisons and additional summaries |
| Raw data | Selected source observations and derived fields, with filters and Excel search |
| Documentation | Data dictionary, definitions, settings and data-quality notes |
| `report.html` | Self-contained browser report with charts; no internet needed |
| Summary CSVs and run receipt | Traceable calculations, software fingerprints, package versions and input/configuration fingerprints |

The workbook is a generated snapshot. Changing cells or filtering raw rows does
not recalculate its analysis or charts. Change settings and rerun to refresh it.
The raw-data sheet includes every supplied source column within the selected scope.

## Boundaries of this release

- Input: CSV or unencrypted XLSX, first worksheet. Your original script used an
  encrypted-Excel reader; this edition does not yet reproduce that step. Convert
  locally using an approved hospital workflow, or retain the original import
  process until an adapter is agreed. Do not add passwords to the software.
- Stable observation, patient and admission identifiers are required. Patient
  names alone cannot reliably identify admissions. The original script does not
  establish which export headers provide these identifiers or a full timestamp.
- Timestamps need an explicit UTC offset and seconds. The import adapter can convert explicitly mapped separate date/time text columns
  with declared UTC offsets. Excel-native date/time representations are not inferred.
  Verify the export mapping before use.
- The analysis treats rows as point observations. Sleep percentages are not
  measured sleep duration. Missing behaviour does not mean recorded absence.
- Experimental significance testing is blocked in the hospital runner. Daily
  changes and sample sizes remain available. Clinical prediction is absent from
  the hospital distribution.

## Acceptance trial and updates

First compare a representative local export with hand-checked source observations
and the established report. Reconcile differences, especially blank codes,
denominators, overnight dates and admission boundaries. Confirm the report helps
the intended clinical review before replacing the working process.

The cheapest useful trial is one ward, several representative stays and both
complete and incomplete records. Pass criteria: all included identities and dates
are correct; spot-checked counts and percentages agree exactly; every material
difference from the old report has an explanation; all four worksheets open and
the analyst can rerun it without editing calculation code. Pause rollout if any
unexplained mismatch remains.

Updates are manual, versioned replacements after acceptance. This package contains
no Git client, updater, server, telemetry or cloud connector. Keep the prior release
until the new one passes the same local checks.
