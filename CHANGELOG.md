# Changelog

## v1.1.0

### Added

* Amass, Findomain, DNSX, Naabu, and Nuclei integrations
* Httpx status code, title, technology, web server, content length, and JSONL output
* JavaScript analysis for likely secrets, API keys, Firebase indicators, JWTs, and GraphQL indicators
* Markdown and HTML reports with summary statistics
* Configurable Nuclei severity, scanner concurrency, and request timeout flags
* Structured `results/` output tree with recon, urls, ports, nuclei, scans, reports, and logs directories
* Detailed security and architecture audit in `docs/AUDIT.md`

### Changed

* Reworked the Bash script into smaller stage functions
* Replaced unsafe package-manager `eval` usage with quoted argv execution
* Validated target domains before filesystem or scanner use
* Streamed active scan jobs instead of materializing the full URL x payload matrix
* Labeled active scanner results as potential findings to avoid overstating confidence

### Fixed

* Prevented path traversal through target names
* Fixed Bash `$` expansion bugs in SQLi and LFI regex checks
* Improved open redirect detection by checking redirect headers without following redirects
* Removed SSRF false positives caused by reflected payload text

## v1.0.0

### Added

* Automatic dependency installer
* Automatic Go installer
* Subdomain enumeration
* Live host detection
* URL collection
* Parameter extraction
* JavaScript file extraction
* Sensitive file discovery
* GF pattern matching
* Active scanning engine
* Parallel execution
* Progress bar support

### Supported Scans

* XSS
* SQLi
* SSRF
* LFI
* Open Redirect

### Output

* Organized recon results
* Organized scan results
* Candidate filtering
