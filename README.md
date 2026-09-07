# Sleep & Behavioural Monitoring

Turn recorded sleep and behaviour observations into charts, patient summaries,
unit comparisons and a clearly defined earlier baseline. Reports are generated
directly: no copying results into a separate Excel chart template.

**Status: runnable synthetic prototype; not clinically validated. Licensing is
pending.** Public visibility does not grant an open-source reuse licence or
authorize operational deployment. See [licensing status](LICENSING.md).

## Try the synthetic report

Install R, download or clone this repository, then run from its folder:

```sh
Rscript --vanilla run.R --demo
```

Open the `report.html` path printed when the command finishes. The demo creates
fully generated observations for six fictional people across two fictional units.
It needs no patient file, account, database connection or additional R package.
After setup, report generation runs locally without a network connection.

Each run creates a folder under `outputs/` containing:

- `report.html`: self-contained charts, patient panels, comparisons and tables.
- `summary-*.csv`: numeric patient, unit, daily, hourly, baseline and quality
  summaries, plus metric definitions.
- `run-receipt.dcf`: software/R versions, input/configuration fingerprints and counts.
- `synthetic-observations.csv`: generated source rows, included only in demo runs.

For Excel input and automatic workbook output, install the optional packages once:

```sh
Rscript --vanilla scripts/install_optional.R
Rscript --vanilla run.R --demo
```

With `openxlsx` installed, `monitoring-report.xlsx` adds summary worksheets and
unit/patient charts. `readxl` enables unencrypted XLSX input. Installation needs
internet access; normal report generation does not.

## What it shows

- Sleep and behaviour proportions by person, admission, time band, day and hour.
- Unit results using pooled observations and an equally weighted mean of admission
  summaries, with contributing-admission counts.
- Changes against a selected earlier baseline from the same person, admission and
  unit; insufficient observations suppress the change calculation.
- Numerators, denominators, missing states and conflicting sleep evidence.

Sleep percentage means **asleep / known sleep-state observations**. Behaviour
percentage means **awake with behaviour recorded / awake with known behaviour
status**. Blank behaviour is unknown, not a recorded absence. Recorded-field
completeness describes rows received; it does not measure missed scheduled checks.

These are descriptive point-observation summaries. They do not establish measured
sleep duration, a medication effect, a behavioural cause, over-sedation or a staffing
requirement. Statistical significance testing and prediction are not implemented.

## Adapt the same core locally

Keep calculation code shared. Copy `config/site.example.dcf` outside the repository
and edit the column mappings, codes, dates, time zone and time bands. Keep local
input and output outside the repository too.

```sh
Rscript --vanilla run.R --config "/local/site.dcf" --input "/local/observations.csv" --output "/local/reports/run-001"
```

Use your actual paths and an empty output directory. Input needs stable observation,
patient and admission identifiers, unit, timestamp, sleep state and behaviour status.
Timestamps require seconds and an explicit UTC offset or `Z`; separate date/time
columns and native Excel dates are not automatically inferred. Read the
[configuration guide](docs/CONFIGURATION.md) before adapting an export.

## Development and remaining work

Run the synthetic regression checks with:

```sh
Rscript --vanilla tests/run_tests.R
```

The [source review](docs/SOURCE_REVIEW.md) records legacy defects and intentional
numerical changes. The [migration plan](docs/MIGRATION.md) identifies remaining
verification. The former Excel visualization template was not supplied: exact
chart/formula parity is unverified. Explicit-interval duration, expected-check
schedules and production deployment controls remain future work.

Do not upload patient records, local reports, credentials or internal configuration
to this repository or its issues. Local reports contain supplied identifiers and
are not encrypted by this tool. Local runs do not export raw input rows; aggregate
reports still require an appropriate destination and access controls.
