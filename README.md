# CSPM-Prowler: Open-Source Cloud Security Posture Management

![Status](https://img.shields.io/badge/status-scan%20successful-brightgreen)
![Prowler](https://img.shields.io/badge/Prowler-v5.33.1-1e3a5f)
![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-Scanned-FF9900?logo=amazonaws&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Containerized-2496ED?logo=docker&logoColor=white)
![Trivy](https://img.shields.io/badge/Trivy-Image%20Scanned-1904DA?logo=aqua&logoColor=white)
![Snyk](https://img.shields.io/badge/Snyk-Container%20Tested-4C4A73?logo=snyk&logoColor=white)
![License](https://img.shields.io/badge/license-Apache%202.0-lightgrey)

## Overview

This project simulates an enterprise Cloud Security Posture Management (CSPM) workflow — the same category of tool as commercial platforms like Wiz — using **Prowler**, a free and open-source CSPM CLI. It was built as a hands-on portfolio piece to demonstrate practical, credential-scoped cloud security auditing mapped to real compliance frameworks, specifically in preparation for cloud security engineering roles that require CSPM platform experience.

**Goal:** Stand up a least-privilege scanning identity via Terraform, run Prowler against a live AWS account, and produce audit-ready findings mapped to named compliance controls (PCI DSS, ISO 27001, SOC 2, and others).

## Architecture

```
Terraform (iam.tf)
      │
      ▼
IAM User: prowler-scan-readonly
  ├─ Policy: SecurityAudit (AWS-managed)
  ├─ Policy: ViewOnlyAccess (AWS-managed)
  └─ Access Key (programmatic only, no console login)
      │
      ▼
Docker container: prowlercloud/prowler:stable
      │
      ▼
610 automated checks across AWS services
      │
      ▼
Findings mapped to 50+ compliance frameworks
(JSON-OCSF / CSV / HTML reports)
```

## Security Design Decisions

- **Least privilege by design:** The scanning identity uses only AWS-managed *read-only* policies (`SecurityAudit`, `ViewOnlyAccess`) — it cannot create, modify, or delete any resource in the account it audits.
- **No console access:** The IAM user has a programmatic access key only; no password, no console login capability.
- **Infrastructure as Code:** The scanning identity itself is provisioned via Terraform, not clicked together manually — reproducible, version-controlled, and destroyable on demand.
- **Ephemeral scanning identity:** The IAM user and its access key were destroyed after the audit, so no long-lived scanning credential remains in the account.
- **Credential hygiene in practice:** An access key was accidentally exposed during development and rotated immediately via `terraform taint` + `terraform apply`, treating any credential typed into a terminal transcript as compromised on principle.

## Tooling

| Tool | Purpose |
|---|---|
| Terraform | Provisions the scoped, read-only IAM scanning identity |
| Docker | Runs Prowler in an isolated container, avoiding the Windows long-path limit that broke a local install |
| Prowler CLI v5.33.1 | Executes 610 automated security checks against the AWS account |
| Trivy | Scans the Prowler container image for known OS and application vulnerabilities |
| Snyk CLI | Second-opinion container scan using a separate vulnerability database |

## Scan Results Summary

**Account scanned:** Personal AWS sandbox account — all regions except `me-central-1`, `me-south-1`

| Metric | Result |
|---|---|
| Total checks executed | 610 |
| Passed | 393 (60.74%) |
| Failed | 251 (38.79%) |
| Muted | 0 |

**Top services by finding volume:**

| Service | Failures | Critical | High |
|---|---|---|---|
| S3 | 100 | 3 | 9 |
| IAM | 58 | 1 | 34 |
| CloudFront | 17 | 0 | 2 |
| CloudWatch | 31 | 0 | 0 |

**Compliance framework results (targeted for this role's focus):**

| Framework | Pass Rate |
|---|---|
| PCI DSS 4.0 | 49.43% |
| ISO 27001:2013 | 34.43% |
| SOC 2 | 62.41% |
| CIS AWS Foundations 2.0 | 52.48% |
| NIST CSF 2.0 | 69.75% |

Full detailed reports (JSON-OCSF, CSV, HTML) are generated per scan in `terraform/output/`. They are excluded from this repo via `.gitignore` because they contain account identifiers and the full list of findings.

## Container Image Assessment (Supply-Chain Check)

Prowler runs with read access to the AWS account it audits, so the scanner itself is part of the attack surface. Before trusting it, the Prowler container image was scanned with two independent tools: **Trivy** and **Snyk**. Both scans were filtered to HIGH and CRITICAL severity.

### Old image vs. current image

| Image | Debian | Snyk issues (HIGH+) | Critical | Vulnerable components |
|---|---|---|---|---|
| Image originally used for the audit, about 4 months old (`sha256:706e7113…`) | 12 (bookworm) | 85 | 7 | 5 of 6 |
| Current `stable` (`sha256:5231a5f5…`) | 13 (trixie) | 13 | 0 | 3 of 6 |

Most critical findings in the older image (zlib, perl, brotli, and the bundled .NET runtime used by PowerShell) already had fixed versions available. Simply running a current image would have removed them.

### Current image: two scanners, two opinions

| Scanner | OS findings (HIGH+) | Critical | Fix available |
|---|---|---|---|
| Trivy | 105 package matches, 27 distinct CVEs | 0 | None. All are `affected` or `fix_deferred` in Debian |
| Snyk | 9 issues | 0 | Not yet for most |

The counts differ because each tool uses its own vulnerability database and severity scoring. Trivy also lists each affected package separately (one `util-linux` CVE appears in 6–7 packages), while Snyk groups them. Running both gives a fuller picture than either one alone.

### Risk assessment

The remaining findings are mainly local privilege-escalation and denial-of-service issues in OS utilities and bundled components. Exploiting them requires an attacker already inside the container. Prowler's run profile limits that exposure:

- One-shot CLI: the container runs the scan and exits, with no long-running service or open ports
- Runs as the non-root `prowler` user (verified with `docker run --rm --entrypoint whoami prowlercloud/prowler:stable`)
- Needs no privileged mode and no Docker socket, only AWS credentials and an output folder mount
- AWS access limited to read-only managed policies plus an explicit deny on mutating actions

**Verdict:** acceptable for short, read-only audit runs, as long as the image is kept current and pinned by digest.

### Lesson: tags move, digests don't

The first Snyk scan unexpectedly reported Debian 12 while Trivy reported Debian 13 for the "same" image. The cause: `prowlercloud/prowler:stable` is a **mutable tag**. Snyk scanned a cached local copy from months earlier, while Trivy pulled the current image from Docker Hub. Pinning by digest (`prowlercloud/prowler@sha256:…`) guarantees that the image scanned is exactly the image that runs.

## Challenges Encountered & Resolved

This section is intentionally kept — the debugging process is part of the demonstrated skill set, not just the end result.

- **Windows long-path limitation:** Local `pip install` failed due to a deeply nested file path exceeding Windows' 260-character default limit. Resolved by running Prowler via Docker instead, so the install happens inside the container's Linux filesystem rather than on Windows.
- **IAM policy syntax:** An initial explicit-deny guardrail policy used a wildcarded service prefix (`*:Create*`), which AWS IAM rejects — service prefixes must be explicit. Resolved by naming each service prefix explicitly (`iam:Create*`, `s3:Put*`, etc.), keeping the deny policy as a second layer of protection on top of the read-only managed policies.
- **Git Bash path mangling:** Docker volume mounts silently failed because Git Bash (MSYS2) rewrites Unix-style paths before passing them to Docker, causing scan output to be written outside the mounted host directory. Resolved using the `//` escape prefix to pass the container-side path through literally.
- **Mutable image tag mismatch:** Trivy and Snyk reported different OS versions for `prowlercloud/prowler:stable`. Traced to a 4-month-old cached image on the local Docker host versus a fresh registry pull. Resolved by pulling the current image and scanning it by digest.
- **Dashboard container networking:** Prowler's interactive dashboard binds to `127.0.0.1` inside the container by default, making it unreachable from the host despite correct Docker port mapping. Static HTML/CSV/JSON reports were used as the primary deliverable instead.

## Status

✅ Prowler successfully authenticated against a least-privilege, Terraform-provisioned IAM identity and completed a full 610-check scan against a live AWS account, producing audit-ready findings mapped to PCI DSS, ISO 27001, SOC 2, and 40+ additional compliance frameworks.

## Future Work (Deferred)

- Wire scans into GitHub Actions for continuous, on-commit compliance checking
- Pin the Prowler image by digest in all run commands, and re-run Trivy/Snyk whenever the digest changes
- Add the container image scan as a gate in the same GitHub Actions workflow
- Build intentionally-misconfigured Terraform resources to demonstrate detection-to-remediation workflow
- Resolve dashboard container networking for live interactive reporting
- Evaluate WSL2 as a native Linux environment to simplify local tooling