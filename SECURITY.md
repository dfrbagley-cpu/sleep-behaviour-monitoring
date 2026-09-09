# Security and sensitive-data reporting

This development preview processes files locally. It does not provide hosted
accounts, access control, encryption of reports or a clinical deployment service.
The newest published release is the review target; there is no guaranteed support
or security-response schedule.

## Reporting

Do not post patient information, credentials, exploitable details or real reports
in public issues. If GitHub shows **Report a vulnerability** under the repository's
Security tab, use that private reporting route with a synthetic reproduction.

If private reporting is unavailable, open a public issue containing only
**"Request for a private security reporting channel"**. Wait for a private route
before supplying sensitive details. Do not attach real records to either route.

Useful report details are the affected version, operating system, entry point,
expected boundary, observed behaviour and minimal synthetic steps to reproduce.

## Local use boundary

- Keep input records, local configuration and generated reports outside the
  repository and in an approved destination.
- Outputs can contain supplied identifiers. The raw-data worksheet retains every
  original source column in its selected scope. Review before sharing.
- Small-cohort suppression is not anonymization. Counts, labels and overlapping
  groups may still disclose information in real local reports.
- HTML escaping and spreadsheet-formula neutralization reduce specific output
  risks; they do not replace control over file access or distribution.
- Release hashes help verify package consistency. They do not establish clinical
  validation or approve a release for a particular environment.

Public examples and automated checks must remain fully synthetic.
