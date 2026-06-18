# Adv-Recon

Advanced bug bounty reconnaissance and active scanning framework for authorized security testing.

Adv-Recon automates subdomain enumeration, DNS resolution, live host discovery, URL collection, JavaScript analysis, port scanning, Nuclei-based vulnerability discovery, GF candidate filtering, and optional active checks for common web bug classes.

## Features

- Dependency bootstrap for Kali/Linux package managers and Go tools.
- Subdomain enumeration with Subfinder, Assetfinder, Amass, and Findomain.
- DNS validation with DNSX and improved lowercase/deduplicated subdomain output.
- Live host discovery with Httpx, including status code, page title, technologies, web server, and content length.
- URL collection with Katana, Gau, and Waybackurls.
- Port discovery with Naabu, saved to `results/ports/ports.txt`.
- Vulnerability discovery with Nuclei and configurable severities.
- JavaScript analysis for likely secrets, API keys, Firebase indicators, JWTs, and GraphQL indicators.
- GF candidate matching for XSS, SQLi, SSRF, LFI, and open redirect.
- Active scanner with safer URL injection, timeout controls, bounded concurrency, and lower-noise detection logic.
- Markdown and HTML reports with summary statistics.

## Installation

```bash
git clone https://github.com/PanchamPatil/Adv-Recon.git
cd Adv-Recon
chmod +x Adv-Recon.sh
```

The script attempts to install missing dependencies automatically. On Kali, run from a user that has `sudo` access or run as root.

## Usage

```bash
./Adv-Recon.sh example.com
```

Optional controls:

```bash
./Adv-Recon.sh example.com --severity medium,high,critical --threads 40 --timeout 12
ADV_RECON_SKIP_INSTALL=1 ./Adv-Recon.sh example.com
```

## Output

```text
results/
├── recon/
│   ├── subs.txt
│   ├── resolved.txt
│   ├── dnsx.txt
│   ├── live.txt
│   ├── live.jsonl
│   └── live-hosts.txt
├── urls/
│   ├── urls.txt
│   ├── params.txt
│   ├── js-files.txt
│   ├── js-findings.tsv
│   └── sensitive-files.txt
├── ports/
│   └── ports.txt
├── nuclei/
│   ├── nuclei.jsonl
│   ├── nuclei.txt
│   └── nuclei-*.jsonl
├── scans/
│   ├── gf-results/
│   └── active/
├── reports/
│   ├── report.md
│   └── report.html
└── logs/
    └── adv-recon.log
```

## Tuning

- `ADV_RECON_CONCURRENCY`: active scanner workers. Default: `30`.
- `ADV_RECON_HTTPX_THREADS`: Httpx threads. Default: `100`.
- `ADV_RECON_URL_THREADS`: Gau threads. Default: `50`.
- `ADV_RECON_JS_THREADS`: JavaScript analysis workers. Default: `20`.
- `ADV_RECON_TIMEOUT`: per-request timeout in seconds. Default: `10`.
- `ADV_RECON_NUCLEI_SEVERITY`: comma-separated severities. Default: `low,medium,high,critical`.
- `ADV_RECON_RESULTS_DIR`: relative output root. Default: `results`.

## Notes

Active checks are intentionally labeled as potential findings. They reduce obvious false positives, but manual validation is still required before reporting anything to a bug bounty program.

## Disclaimer

This tool is intended for authorized security testing, educational purposes, and bug bounty programs only. Users are responsible for complying with all applicable laws, program scopes, and authorization requirements.

## License

MIT License
