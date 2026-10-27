# LinkTrace

**LinkTrace** is a Bash-based website reference discovery and evidence collection tool. It coordinates Subfinder, ProjectDiscovery httpx, Katana and `jq` to discover candidate hosts, identify responsive web services, crawl pages, and produce reports for a supplied search term.

LinkTrace is designed to help answer questions such as: **Which pages on an authorized site link to, or contain a reference to, a particular domain or phrase?** It is a reference-finding utility, not a vulnerability scanner.

## Authorized use

Use LinkTrace only on websites and assets you own or have explicit permission to assess. Subfinder uses passive sources, while httpx sends HTTP requests and Katana actively crawls pages. Confirm the permitted scope and respect the site's terms, rate limits, privacy requirements and operational constraints. Do not use LinkTrace to bypass authentication, evade access controls, collect private information, or disrupt a service.

The current crawl configuration is bounded to depth 3, a rate of 5 requests per second, and a maximum duration of 5 minutes. These limits do not guarantee a small number of total requests across all seeds. Only change them when you are authorized to do so.

## How it works

1. Parses `--site` and `--find`.
2. Extracts the hostname from the supplied HTTPS URL while preserving the original URL as a crawl seed.
3. Runs Subfinder against the supplied hostname and saves candidate subdomains.
4. Combines the original hostname with Subfinder results, then sorts and removes duplicates.
5. Runs ProjectDiscovery httpx against the host list and saves responsive URLs.
6. Combines the original URL with the responsive URLs to build Katana's seed list.
7. Runs Katana with bounded crawl settings, writing JSONL crawl records and stored response artifacts.
8. Writes broad matching records to `findings.jsonl` and runs the evidence report generator to create JSONL, CSV and Markdown reports.

**Subfinder scope note:** Subfinder receives the hostname extracted from `--site`. LinkTrace does not automatically determine the registrable root domain. If the supplied URL uses a subdomain, Subfinder enumerates from that supplied hostname rather than automatically finding sibling subdomains across the parent domain.

## Requirements

LinkTrace is intended for Linux environments such as Kali Linux.

- Bash 4 or newer
- Git, for cloning the repository
- `jq`, for parsing Katana JSONL and generating reports
- ProjectDiscovery Subfinder
- ProjectDiscovery httpx
- ProjectDiscovery Katana
- Standard Linux command-line utilities, including `cat`, `cut`, `grep`, `mkdir`, `mktemp`, `sort`, `tr` and `wc`

Python is not required by the current Bash workflow. Go is **not required to run LinkTrace** when using precompiled tool binaries. Go is required only if you choose to install/build the ProjectDiscovery tools from source using `go install`.

## Installation

### 1. Install system prerequisites

On Kali Linux or a compatible Debian-based system:

```bash
sudo apt update
sudo apt install -y git jq curl unzip
```

### 2. Install the ProjectDiscovery tools

Download the appropriate precompiled release for your operating system and CPU architecture from the official release pages:

- [Subfinder releases](https://github.com/projectdiscovery/subfinder/releases)
- [ProjectDiscovery httpx releases](https://github.com/projectdiscovery/httpx/releases)
- [Katana releases](https://github.com/projectdiscovery/katana/releases)

Extract the binaries and place them in a directory on your `PATH`, such as `~/.local/bin` or `/usr/local/bin`. Follow the release instructions for the binary you download. The directory must be on `PATH` for LinkTrace to find the tools.

Alternatively, install from source using the official instructions. That method requires Go, and the minimum supported Go version can change between tool releases:

- [Subfinder installation](https://docs.projectdiscovery.io/tools/subfinder/install)
- [httpx installation](https://docs.projectdiscovery.io/tools/httpx/install)
- [Katana repository and installation](https://github.com/projectdiscovery/katana)

Some Subfinder passive sources require provider API credentials. Without configured credentials, discovery may still run but coverage can be reduced.

### 3. Clone LinkTrace

Replace `<REPOSITORY_URL>` with the URL of your GitHub repository:

```bash
git clone <REPOSITORY_URL> LinkTrace
cd LinkTrace
chmod +x linktrace.sh
```

Keep the repository's file names and directories intact. The main script locates its helper files relative to its own location.

### 4. Verify the dependencies

```bash
jq --version
subfinder -version
httpx -version
katana -version
```

On some Kali installations, ProjectDiscovery httpx is named `httpx-toolkit`. LinkTrace checks for `httpx-toolkit` first and then `httpx`, and verifies the executable's help output to avoid selecting an unrelated program with the same name.

## Usage

```bash
./linktrace.sh --site 'https://portal.example.org/reference' --find 'vendor.example.net'
```

Arguments:

- `--site`: an HTTPS URL to use as the starting point. The original path is preserved as a crawl seed.
- `--find`: text or a domain to search for in collected crawl records and response data.
- `--help`: display command-line help.

Quote the URL and search term so the shell does not interpret special characters. The current URL validation expects an HTTPS URL with a conventional DNS hostname; explicit ports and IPv6 address literals are not supported by the hostname validation logic.

## Repository layout

```text
LinkTrace/
├── linktrace.sh
├── lib/
│   └── dependencies.sh
├── scripts/
│   └── evidence_report.sh
├── README.md
├── .gitignore
└── linktrace_results/          
```

`linktrace.sh` orchestrates the scan. It sources `lib/dependencies.sh` for tool discovery and dependency checks, then executes `scripts/evidence_report.sh` after crawling. Keep these paths and names consistent with the commands in the main script.

## Where results are stored

LinkTrace writes results beneath `linktrace_results/` in the repository directory. Every scan gets a separate folder with a name similar to:

```text
linktrace_results/
└── run-27-10-2026_22-30-15-12345/
```

The name uses the local date and time (`DD-MM-YYYY_HH-MM-SS`) plus the process ID to reduce naming collisions. Existing scan results are kept in their own folders rather than intentionally reused.

A typical run directory contains:

```text
run-DD-MM-YYYY_HH-MM-SS-PID/
├── subdomains.txt
├── hosts.txt
├── live-urls.txt
├── crawl-seeds.txt
├── crawl.jsonl
├── findings.jsonl
├── verified-links.jsonl
├── response-matches.jsonl
├── evidence-results.jsonl
├── evidence-results.csv
├── evidence-report.md
└── responses/
```

| Output                   | Description                                                                                                                                                                                    |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `subdomains.txt`         | Subfinder's discovered subdomains. It can be empty even when Subfinder exits successfully.                                                                                                     |
| `hosts.txt`              | Original hostname and discovered hostnames, sorted and deduplicated.                                                                                                                           |
| `live-urls.txt`          | URLs reported by httpx as responsive. It can be empty when no host responds.                                                                                                                   |
| `crawl-seeds.txt`        | The original full URL plus available responsive URLs, with duplicates removed.                                                                                                                 |
| `crawl.jsonl`            | Katana's structured crawl output: one JSON record per line.                                                                                                                                    |
| `findings.jsonl`         | Raw crawl records whose complete JSON line contains the search term. This is a broad first-pass match and is not a count of unique links.                                                      |
| `responses/`             | Request and response artifacts saved by Katana.                                                                                                                                                |
| `verified-links.jsonl`   | Records where the endpoint matches the term and Katana metadata identifies an HTML `a` tag with an `href` attribute. Review the source and destination before treating a record as definitive. |
| `response-matches.jsonl` | Records whose captured response body contains the term. A body match may occur in markup or scripts and is not necessarily visible page text.                                                  |
| `evidence-results.jsonl` | Combined, deduplicated link and response-body records.                                                                                                                                         |
| `evidence-results.csv`   | Spreadsheet-friendly export of the combined evidence.                                                                                                                                          |
| `evidence-report.md`     | Human-readable summary of the report results.                                                                                                                                                  |

## View the latest report

Run this from the repository directory:

```bash
latest_run=$(find linktrace_results -mindepth 1 -maxdepth 1 \
  -type d -name 'run-*' -printf '%T@ %p\n' \
  | sort -nr | head -n 1 | cut -d ' ' -f 2-)

cat "$latest_run/evidence-report.md"
```

## Interpreting results

- A match in `findings.jsonl` means the term appeared somewhere in the serialized JSON record. It may match a destination URL, source URL, metadata or response body.
- `verified-links.jsonl` narrows results to records whose endpoint matches the term and whose metadata identifies an anchor `href`. The report reflects Katana's recorded metadata; review the original evidence if the distinction is important.
- `response-matches.jsonl` means the term occurred somewhere in the captured response body. It may be in HTML, scripts, or other content and does not establish that the term was displayed to a user.
- Matching-record counts are not automatically counts of unique links or pages.
- No match means the term was not found in the data captured by that run; it does not prove the term is absent from the entire website.
- Crawling is best-effort, not exhaustive. Unlinked pages, authenticated content, JavaScript-rendered content that the configured crawler does not expose, network failures and time limits can result in missed pages.
- Katana's `-do` option records discovered out-of-scope endpoints; it does not mean those external sites are crawled without limit.

## Troubleshooting

**`jq` is missing**

```bash
sudo apt install jq
```

**A dependency is missing or rejected**

Confirm the correct ProjectDiscovery binary is installed and its directory is on `PATH`. The dependency helper checks tool help output as well as executable availability.

**`subdomains.txt` is empty**

Subfinder may finish successfully without finding additional subdomains. Available passive sources and their provider credentials affect coverage.

**`live-urls.txt` is empty**

No candidate host may have responded to httpx. This alone does not prove LinkTrace or httpx is broken.

**`crawl.jsonl` is empty**

Check that `crawl-seeds.txt` exists and contains at least one valid URL. Review Katana's error messages; a successful crawl with no records is different from a crawler startup failure.

## Repository hygiene

The repository's `.gitignore` should exclude generated scan data:

```gitignore
/linktrace_results/
__pycache__/
*.pyc
```

Scan artifacts may be large and can contain copied page content. Do not commit API credentials, provider configuration, session data or captured information that you are not authorized to publish.

## Official documentation

- [Subfinder](https://github.com/projectdiscovery/subfinder)
- [Subfinder installation](https://docs.projectdiscovery.io/tools/subfinder/install)
- [ProjectDiscovery httpx](https://github.com/projectdiscovery/httpx)
- [httpx installation](https://docs.projectdiscovery.io/tools/httpx/install)
- [Katana](https://github.com/projectdiscovery/katana)
- [jq manual](https://jqlang.org/manual/)

## Current limitations

LinkTrace currently provides a discovery-to-crawl pipeline and produces raw and structured evidence reports from the captured Katana data. Subfinder enumerates the hostname supplied to it rather than automatically identifying the registrable root domain. The matcher's results are best-effort and depend on the pages and response bodies collected during the crawl. Review evidence before drawing conclusions.
