# Adv-Recon Security, Performance, and Architecture Audit

Date: 2026-06-18

Scope reviewed:

- `Adv-Recon.sh`
- `payloads/*.txt`
- `README.md`
- `CHANGELOG.md`

## Executive Summary

The original project was a compact Bash-based bug bounty recon workflow with useful coverage, but it concentrated all behavior in one large script and had several high-impact safety and reliability risks. The most important issues were unsafe shell command construction with `eval`, direct filesystem use of unvalidated user input, fragile dependency installation, weak tool coverage for modern recon pipelines, expensive active-scan job materialization, and detection logic that could both miss real issues and produce noisy results.

The current patch keeps the single-script workflow for backward usability while introducing a safer internal architecture:

- Validated and normalized domain input.
- Fixed `results/` output tree.
- Structured logging.
- Safer package manager execution without `eval`.
- Amass, Findomain, DNSX, Naabu, and Nuclei support.
- Richer Httpx probing.
- JavaScript indicator extraction.
- Markdown and HTML reporting.
- Better active scanner timeout, concurrency, and detection behavior.

## Vulnerabilities And Bugs Found

### High Priority

1. Unsafe package command execution

   The previous installer built strings such as `PKG_INSTALL="$SUDO apt-get install -y"` and executed them with `eval`. Package names were mostly internal, but `eval` is unnecessary and dangerous in an installer. The patch replaces this with package-manager-specific argv execution.

2. Directory traversal and unsafe output path

   The previous code used:

   ```bash
   DOMAIN=$1
   mkdir -p "$DOMAIN"
   cd "$DOMAIN"
   ```

   A target like `../../somewhere` could move output outside the project. The patch normalizes and validates domains, rejects unsafe targets, and writes to `results/`.

3. Active scanner false positives

   SSRF detection treated reflected payload text as a hit, which is not evidence of SSRF. Redirect checks followed redirects with `-L`, making `Location` validation unreliable. SQLi and LFI regex strings included `$$$$` / `$$...$$` patterns that Bash expands inside double quotes. The patch removes the SSRF echo check, checks redirect headers without following, and fixes the regexes.

4. Unbounded job-file growth

   The previous active scanner generated a complete URL x payload job file before scanning. For 100k URLs and larger payload sets, this can create millions of lines before a single request starts. The patch streams jobs into bounded `xargs` workers.

### Medium Priority

1. Fragile dependency installation

   Parallel `go install` improves speed but can fail noisily on slow links or constrained hosts. The patch installs Go tools sequentially for reliability and logs installation output.

2. Weak live host output

   `httpx` previously only wrote live URLs. Bug bounty triage benefits from metadata, so the patch collects status code, title, technologies, server, content length, and JSONL.

3. Missing recon engines

   Amass, Findomain, DNSX, Naabu, and Nuclei were requested and missing. The patch integrates them while keeping Amass/Findomain optional so older Kali setups do not block the run.

4. Limited reporting

   The original script printed terminal counts but did not persist a report. The patch generates `results/reports/report.md` and `results/reports/report.html`.

5. No central logging

   Errors were commonly discarded to `/dev/null`. The patch writes command output and warnings to `results/logs/adv-recon.log`.

### Low Priority

1. Encoding noise in banner and docs

   Some Unicode banner text rendered as mojibake in this workspace. The patch uses ASCII text for portability.

2. Scanner wording

   The original active scanner called findings `VULN`. The patch labels them `POTENTIAL` because most lightweight active checks still require manual confirmation.

3. Payload coverage

   The included payload files are intentionally tiny. They are useful smoke-test payloads, not comprehensive wordlists.

## Refactored Code Suggestions Implemented

- Split the script into focused functions: argument parsing, output initialization, dependency install, recon, live discovery, port scan, URL collection, GF matching, JS analysis, Nuclei, active scans, and reporting.
- Added validated CLI options for severity, concurrency, timeout, and install skipping.
- Replaced shell-string commands with quoted command arguments.
- Added output variables for all result locations instead of relying on `cd`.
- Added helper functions for URL/domain normalization, line counting, logging, and report generation.
- Kept active scan menu behavior for compatibility.

## Scanner Accuracy Improvements

### XSS

The scanner still uses reflected-payload detection, but it now reports `POTENTIAL` instead of `VULN`. This avoids overstating reflected text as confirmed script execution.

### SQLi

The SQL error regex now avoids Bash PID expansion bugs and includes additional database error indicators. It remains error-based and should be supplemented with Nuclei and manual testing.

### SSRF

Reflected callback payloads are no longer considered SSRF. The check now looks for cloud metadata and metadata-service indicators in the response body.

### LFI

The LFI regex no longer suffers from Bash `$` expansion. It checks Linux and Windows file disclosure indicators.

### Open Redirect

Redirect detection now checks the first `Location` header without following redirects and confirms that the payload host differs from the original host.

## Recommended Project Architecture

The script is now safer, but long term this project should move from one large Bash script into a small Go application plus shell installer.

Recommended layout:

```text
cmd/adv-recon/
internal/config/
internal/install/
internal/recon/
internal/httpx/
internal/ports/
internal/nuclei/
internal/jsanalysis/
internal/scanner/
internal/report/
payloads/
scripts/install-tools.sh
docs/
```

Go should own configuration, concurrency, file streaming, JSONL parsing, report generation, and active scan orchestration. Bash should be limited to bootstrapping dependencies for Kali and other Linux distributions.

## Performance Review

Current patch improvements:

- Streams active scan jobs instead of materializing a full job matrix.
- Uses `sort -u` as an external dedup mechanism rather than storing all URLs in Bash arrays.
- Keeps concurrency configurable.
- Applies curl timeouts and connect timeouts consistently.
- Avoids running optional tools as blockers.

Further performance work:

- Convert active scanner to Go worker pools with context cancellation.
- Use JSONL throughout for live hosts, URLs, and findings.
- Implement per-host rate limiting.
- Add resumable stages that skip completed outputs unless `--force` is set.
- Add scope-aware URL normalization to dedupe query-parameter permutations.

## Kali Compatibility Notes

- The script remains Bash-oriented and uses GNU userland patterns that are standard on Kali.
- Naabu may require packet capture dependencies and privileges depending on scan mode. The installer attempts `libpcap-dev` on apt systems.
- ProjectDiscovery tools are installed with Go when not present.
- Amass and Findomain are optional because package availability varies across distributions and versions.

## Exact Patch Summary

Main code patch:

- Replaced the original `Adv-Recon.sh` implementation with a safer staged workflow.
- Updated `README.md` for the new features and output tree.
- Added this audit report.

Use `git diff` in the repository to inspect the exact line-by-line patch.

## Roadmap

### v1.1

- Add `--non-interactive`, `--active-scan`, and `--payload-dir` flags.
- Add Kali smoke-test workflow in CI.
- Add ShellCheck and shfmt.
- Add resumable stage checks.
- Add output compatibility symlinks or migration notes for users expecting the old target-named folder.

### v1.5

- Move report generation to structured JSONL inputs.
- Add per-host concurrency caps and backoff.
- Add URL normalization by parameter key sets.
- Add scope file support for bug bounty programs.
- Add Nuclei template profile presets.

### v2.0

- Rebuild orchestration in Go.
- Keep Bash as `scripts/install-tools.sh`.
- Add typed config files and profiles.
- Add unit tests for domain validation, URL dedupe, and finding parsing.
- Add integration tests with local vulnerable fixtures.

### v3.0

- Distributed scan mode with resumable job queues.
- Web dashboard for large programs.
- Historical diffing between runs.
- Finding confidence scoring.
- Provider-aware SSRF/OOB integrations.
- Plugin system for custom recon sources and vulnerability modules.
