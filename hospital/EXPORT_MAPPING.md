# Mapping the hospital export

The new shared engine requires the following contract. The original R script was
reviewed, but it does not identify all of the source fields needed for admission
and chronological analysis. Confirm missing mappings against an export **locally**.

| Configuration field | Meaning | Evidence from original script |
| --- | --- | --- |
| ObservationIdColumn | Unique observation identifier | Header not established |
| PatientIdColumn | Stable person identifier | `PAT_NAME` was used for selection; obtain a stable identifier |
| EpisodeIdColumn | Stable admission/stay identifier | Header not established |
| UnitColumn | Ward on the observation | `DEPT_NAME` |
| TimestampColumn | Date and time with seconds and explicit UTC offset | `TIME` supplied a clock time; full timestamp header not established |
| SleepStateColumn | Explicit awake/asleep state | `AWAKE.ASLEEP` |
| BehaviourColumn | Explicit presence/absence of any behaviour | `BEHAVIOURS`; YES appears in original logic, absence coding needs verification |
| AwakeCalmColumn | Optional fallback flag | `AWAKE.CALM`, value `Awake/Calm` |
| SleepingColumn | Optional fallback flag | `SLEEPING`, value `Sleeping` |

Excel/CSV headers are preserved literally. R's earlier `data.frame` call may have
changed spaces to dots; use the actual headings in the new import, not an assumed
dot-converted spelling. Leave optional fallback column mappings blank if absent.
Add `BehaviourTypes` only for verified individual flag columns. Blank values stay
unknown; do not fill them with NO without confirming their source meaning.

The demo's `synthetic-observations.csv` is a complete example of the canonical
format. It demonstrates the contract; it is not a substitute for verifying the
hospital export. Do not invent admission IDs, derive stable IDs from names, or
assign one fixed UTC offset to an export spanning a daylight-saving change.

For explicit conversion of separate date/time fields and mapped headings, see
`docs/IMPORT_ADAPTER.md`. The adapter preserves verified source IDs and does not
invent missing admission or person keys.
