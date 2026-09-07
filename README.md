# Sleep & Behavioural Monitoring Tool

A project to make sleep and behavioural observation reports easier to configure, maintain, and interpret.

**Status: repository foundation.** The existing R application has not yet been imported. This repository does not currently contain a runnable application, clinical calculations, or patient data. There is no validated release to install.

## Intended use

The planned tool brings sleep and behavioural observations together to support patient reviews, discussions with families, and operational planning. It will show patterns over time, comparisons with a selected patient baseline, and the completeness of the underlying observations.

Outputs are intended to support professional interpretation. Observed sleep patterns alone will not be labelled as a diagnosis of over-sedation; time-of-day patterns will not be presented as proof of a behavioural trigger.

## What this repository contains

- [Source migration and validation plan](docs/MIGRATION.md).
- [Licensing status](LICENSING.md).
- Git exclusions for local data, credentials, R sessions, and generated reports.

## Next development milestone

Bring in the existing R source for review, replace organization-specific settings with configuration, and reproduce its reports using fully generated synthetic observations. The first runnable release should have one documented demo command and one environment configuration file.

The public version and future local deployments should use the same tested calculation functions. Data connections, column mappings, observation codes, report labels, and local paths should be configured outside those functions.

No production database, hospital network, or account should be required to run the planned synthetic demo. Exact installation commands and dependencies will be documented after the existing source has been inspected and tested.

## Data boundaries

Public examples must be generated from scratch. Do not upload patient records, clinical reports, identifiers, credentials, internal documents, or screenshots containing real data to this repository or its issues. Renaming real patients is not the synthetic-data approach used here.

Keep original source pending review, local configuration, input data, and generated reports outside the repository. `.gitignore` is an extra guard against accidental staging; it does not inspect files, remove earlier commits, or prevent a forced addition.

## Licensing

Licensing terms have not yet been selected. Public visibility does not mean this project has an open-source licence. See [LICENSING.md](LICENSING.md) before planning reuse or deployment.
