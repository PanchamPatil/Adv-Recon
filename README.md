# Adv-Recon 🚀

Advanced Bug Bounty Recon & Active Scanning Framework

Adv-Recon is an automated reconnaissance and vulnerability discovery framework designed for bug bounty hunters and security researchers. It automates subdomain enumeration, live host detection, URL gathering, JavaScript discovery, sensitive file identification, GF pattern matching, and active vulnerability scanning.

## Features

* Automatic dependency installation
* Automatic Go installation
* Subdomain Enumeration

  * Subfinder
  * Assetfinder
* Live Host Detection

  * Httpx
* URL Collection

  * Katana
  * Gau
  * Waybackurls
* JavaScript Discovery
* Sensitive File Discovery
* GF Pattern Matching

  * XSS
  * SQLi
  * SSRF
  * LFI
  * Open Redirect
* Active Vulnerability Scanning
* Parallel Processing
* Progress Tracking
* Organized Output Structure

## Installation

```bash
git clone https://github.com/PanchamPatil/Adv-Recon.git
cd Adv-Recon
chmod +x Adv-Recon.sh
```

## Usage

```bash
./Adv-Recon.sh example.com
```

## Output

```text
target.com/
├── subs.txt
├── live.txt
├── urls.txt
├── params.txt
├── js-files.txt
├── sensitive-files.txt
├── gf-results/
└── scan-results/
```

## Disclaimer

This tool is intended for authorized security testing, educational purposes, and bug bounty programs only.

Users are responsible for complying with all applicable laws and authorization requirements.

## License

MIT License

## Author

Pancham Patil

