# Preparing a hospital export locally

The adapter translates **explicitly mapped** CSV or unencrypted XLSX exports into
the input format used by the Hospital R Tool. It runs on your computer, does not
upload data, and does not change the source file. CSV conversion uses base R;
XLSX conversion requires the optional, locally installed `readxl` package.

This is a mapping tool, not a completed mapping for a particular hospital. Verify
headings, source codes and timestamps against your export locally. Do not upload
patient files or the original password-containing script to GitHub. Password-
protected XLSX import is not supported; use your approved local export workflow.

## First run

1. Copy `config/import.example.dcf` to a local `import.dcf` outside the repository.
   The example maps the synthetic demo's canonical headings; replace them with
   the literal headings in your hospital export. Adjust report and baseline dates.
2. Map existing unique observation, stable person, admission/stay and ward fields.
   Names are not stable patient identifiers. Do not generate admission IDs from
   names, dates or row numbers. If these keys are missing, obtain them upstream.
3. Choose the timestamp mode below. Confirm sleep/behaviour codes; leave optional
   fallback column mappings blank when absent. Add individual behaviour flags
   only when their source meanings are known.
4. Run from the extracted tool folder, using a **new empty directory**:

```sh
Rscript --vanilla scripts/prepare_hospital_input.R --config "path/to/import.dcf" --input "path/to/export.csv" --output "path/to/prepared/new-run"
```

For XLSX, replace the input extension. The first worksheet is read; export the
intended worksheet separately if the workbook contains several. Use text cells
for identifiers. Leading zeroes already removed by Excel cannot be recovered.

The output contains `observations.csv`, `hospital.dcf` and `import-receipt.dcf`.
Set `mode = "local"` in `hospital/settings.R`, and point `input_file` and
`config_file` at the first two files. Run `run_hospital.R` to create the report.
The generated configuration preserves your report dates, time bands, state codes
and explicit behaviour mappings, and disables experimental inference.

## Timestamp modes

| Mode | Required configuration | Accepted example |
| --- | --- | --- |
| `iso` | `TimestampColumn`; leave separate date/time/offset settings blank | `2026-08-01T08:30:00-04:00`, `2026-08-01T12:30:00Z` |
| `split` | `DateColumn`, `TimeColumn`, `DateFormat`, `TimeFormat`; leave `TimestampColumn` blank | `01/08/2026`, `08:30:00`, offset `-04:00` |

Both modes require `Timezone`, such as `America/Toronto`. In ISO mode, the source
timestamp already identifies an instant and is preserved. The report timezone
controls which local day and time band contain that instant.

For separate local date/time fields, configure **one** offset source:
`UTCOffsetColumn` for a per-row explicit offset, or `UTCOffset` for a fixed value.
Offsets accept `Z`, `+HHMM`, `-HHMM`, `+HH:MM` or `-HH:MM`. Every resulting local
time is checked against the configured IANA timezone. A fixed `-05:00` fails for
Toronto observations during daylight time. Nonexistent spring-forward times fail.
The two fall-back occurrences are accepted only with their respective explicit
offsets; the adapter never chooses an occurrence for you.

An example replacement block for a **hypothetical**, locally verified export:

```text
TimestampMode: split
TimestampColumn:
DateColumn: Observation date
TimeColumn: Observation time
DateFormat: %d/%m/%Y
TimeFormat: %H:%M:%S
UTCOffsetColumn: UTC offset
UTCOffset:
```

Date formats are limited to `%Y-%m-%d`, `%d/%m/%Y` and `%m/%d/%Y`; time formats
to `%H:%M` and `%H:%M:%S`. Exact zero-padded text is required. Excel serial dates,
decimal time fractions, locale-dependent dates and AM/PM text are not inferred.
Export or convert those cells to the selected text representation locally first.

## Mappings and source values

The earlier R workflow used headings such as `AWAKE.ASLEEP`, `AWAKE.CALM`,
`SLEEPING`, `BEHAVIOURS` and `DEPT_NAME`. Those dotted headings may have resulted
from R converting spaces or punctuation. The adapter preserves literal export
headers; do not assume a dotted heading is present in the Excel file.

`BehaviourTypes` uses `Label=source heading|Another label=another heading`.
These become canonical `behaviour_type_001` columns with the supplied labels in
`hospital.dcf`. The same explicit yes/no code sets apply to each behaviour flag.
Blank or unmapped states stay blank or unmapped; **blank never becomes NO**.
Fallback flags retain their source values and the shared engine resolves or flags
them when reporting.

Only mapped fields are copied by default. To retain additional approved raw fields,
list their exact headings in `ExtraColumns`, separated by `|`. These extras keep
their names and values for the raw-data worksheet; a name that conflicts with a
canonical field is rejected. All source rows are retained in the prepared CSV;
report dates and patient/ward scope are applied when creating the report. Keep
both the export and prepared files within the approved local data location.

`observations.csv` is machine input. Do not open and resave it in Excel: that can
change identifiers, timestamps and formula-like text. Use the generated workbook
for human review; the report writer neutralizes formula-like source values there
without changing the calculation input.

Duplicate observation IDs and duplicate patient/admission/instant combinations
are rejected before writing. Missing mapped columns, ambiguous mappings, malformed
dates and offsets are rejected too. IDs with surrounding whitespace fail so keys
are not silently changed. Error messages identify source **row numbers**, not
patient values. The receipt contains version, row counts and file hashes only;
it does not include patient IDs, source paths or clinical values. Its issue count
covers the configured report/baseline selection, not all rows in the export.

Successful conversion confirms the input contract. It does not establish clinical
validity or prove that an organization's source definitions were mapped correctly.
