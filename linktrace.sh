#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dependencies.sh"

site=""
find_term=""

while (($# > 0)); do

	case "$1" in --site)

		if (($# < 2)); then
			echo "ERROR: site term is missing"
			exit 2
		fi

		site="$2"

		if [[ -z "$site" ]]; then
			echo "STRING CANNOT BE EMPTY"
			exit 2
		fi
		if [[ "$site" == -* ]]; then
			echo "TARGET LINK CANNOT START WITH ANOTHER FLAG"
			exit 2
		fi

		if [[ "$site" != https://?* ]]; then
			echo "ERROR: Site must start with https:// and contain a value after it"
			exit 2
		fi

		shift 2

		;;

	--find)

		if (($# < 2)); then
			echo "ERROR: Search term is missing"
			exit 2
		fi

		find_term="$2"

		if [[ -z "$find_term" ]]; then
			echo "STRING CANNOT BE EMPTY"
			exit 2
		fi
		if [[ "$find_term" == -* ]]; then
			echo "TARGET LINK CANNOT START WITH ANOTHER FLAG"
			exit 2
		fi

		shift 2

		;;

	--help)
		echo "LinkTrace - Website reference evidence collector

Usage:
  ./LINKTREE.SH --site https://example.com --find scholars.net

Options:
  --site URL    Target website
  --find TEXT   Text or domain to search for
  --help        Display this help"

		exit 0
		;;
	*)
		echo "ERROR: Unknown option: $1"
		exit 2

		;;
	esac
done
if [[ -z "$site" || -z "$find_term" ]]; then
	echo "ERROR: Both --site and --find are required."
	exit 2
fi
if ! check_dependencies; then
	exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
	printf 'ERROR: jq is required. Install it with: sudo apt install jq\n' >&2
	exit 1
fi
echo "Target: $site"
echo "Search: $find_term"

#subfinder operations
# URL normalization: extract the hostname from the supplied URL.

host_without_https="${site#https://}"             # Remove the https:// prefix.
host_without_pattern="${host_without_https%%/*}"  # Remove the path and everything after the first slash.
host_without_query="${host_without_pattern%%\?*}" # Remove the query string, starting at the literal '?'.
host_without_fragment="${host_without_query%%#*}" # Remove the fragment, starting at '#'.

host="$host_without_fragment" # Store the normalized hostname.
echo "Host:$host"

# url validation
if [[ ! "$host" =~ ^[A-Za-z0-9.-]+$ ]]; then
	printf 'ERROR: Invalid hostname: %s\n' "$host" >&2
	exit 2
fi
# Reject hostnames exceeding the maximum permitted length.
if [[ ${#host} -gt 253 ]]; then
	printf 'ERROR: Hostname exceeds 253 characters.\n' >&2
	exit 2
fi

# Count the number of dots in the hostname.
host_dots=$(printf '%s' "$host" | tr -cd '.' | wc -c)

# Iterate through every DNS label.

# A hostname with N dots contains N + 1 labels.
for ((i = 1; i <= $host_dots + 1; i++)); do

	# Extract the current label, using the dot as the field delimiter.
	label=$(printf '%s' "$host" | cut -d '.' -f "$i")

	# Reject the hostname if a label is empty, exceeds 63 characters,

	# or begins or ends with a hyphen.
	if [[ -z "$label" || ${#label} -gt 63 || "$label" == -* || "$label" == *- ]]; then

		# Report the invalid hostname to the user.
		echo "ERROR: Invalid hostname: $host"

		# Exit with status 2 to indicate invalid user input.
		exit 2
	fi

done

result_dir="$SCRIPT_DIR/linktrace_results"
run_dir="$result_dir/run-$(date +%d-%m-%Y_%H-%M-%S)-$$"
subdomains_file="$run_dir/subdomains.txt"

if ! mkdir -p -- "$result_dir"; then

	printf 'ERROR: Could not create results directory: %s\n' "$result_dir" >&2
	exit 1

fi

if ! mkdir -- "$run_dir"; then
	printf 'ERROR: Could not create scan directory: %s\n' "$run_dir" >&2
	exit 1
fi
hosts_file="$run_dir/hosts.txt"
printf 'Subfinder output: %s\n' "$subdomains_file"

subfinder_bin="$(find_pd_tool subfinder)"

if ! "$subfinder_bin" -d "$host" -silent -o "$subdomains_file" >/dev/null; then
	printf 'ERROR: Subfinder failed for target: %s\n' "$host" >&2
	exit 1
fi

printf '%s\n' "$host" >"$hosts_file"

if ! cat -- "$subdomains_file" >>"$hosts_file"; then

	printf 'ERROR: Could not append Subfinder results from %s\n' "$subdomains_file" >&2
	exit 1
fi

if ! sort -u "$hosts_file" -o "$hosts_file"; then
	printf 'ERROR: Could not Sort results from %s\n' "$hosts_file" >&2
	exit 1
fi

#httpx:

live_urls_file="$run_dir/live-urls.txt"
httpx_bin="$(find_pd_tool httpx)"

if ! "$httpx_bin" -l "$hosts_file" -silent -o "$live_urls_file" >/dev/null; then
	printf 'ERROR: httpx failed for target: %s\n' "$host" >&2
	exit 1
fi

# Prepare starting URLs for Katana, preserving the original full URL.
crawl_seeds_file="$run_dir/crawl-seeds.txt"

if ! printf '%s\n' "$site" >"$crawl_seeds_file"; then
	printf 'ERROR: Could not create crawl-seed file: %s\n' "$crawl_seeds_file" >&2
	exit 1
fi

# Add responsive URLs when httpx has produced results.
if [[ -s "$live_urls_file" ]]; then
	if ! cat -- "$live_urls_file" >>"$crawl_seeds_file"; then
		printf 'ERROR: Could not append live URLs to crawl seeds.\n' >&2
		exit 1
	fi
fi

# Remove duplicate starting URLs.
if ! sort -u "$crawl_seeds_file" -o "$crawl_seeds_file"; then
	printf 'ERROR: Could not sort crawl seeds: %s\n' "$crawl_seeds_file" >&2
	exit 1
fi
# Katana output paths
crawl_results_file="$run_dir/crawl.jsonl"
crawl_response_dir="$run_dir/responses"
katana_bin="$(find_pd_tool katana)"

if ! mkdir -p -- "$crawl_response_dir"; then
	printf 'ERROR: Could not create response directory: %s\n' "$crawl_response_dir" >&2
	exit 1
fi

if ! "$katana_bin" -silent -list "$crawl_seeds_file" -d 3 -rl 5 -ct 5m -jsonl -do -o "$crawl_results_file" -sr -srd "$crawl_response_dir" >/dev/null; then
	printf 'ERROR: Katana failed for target: %s\n' "$host" >&2
	exit 1
fi

# Prepare the findings output file.
findings_file="$run_dir/findings.jsonl"
matches_found=0
term_lower="${find_term,,}"

# Ensure the crawl output exists before searching it.
if [[ ! -f "$crawl_results_file" ]]; then
	printf 'ERROR: Crawl output file not found: %s\n' "$crawl_results_file" >&2
	exit 1
fi

# Create or clear the findings file for this run.
if ! : >"$findings_file"; then
	printf 'ERROR: Could not create findings file: %s\n' "$findings_file" >&2
	exit 1
fi

# Read the crawl records one line at a time.
while IFS= read -r line || [[ -n "$line" ]]; do
	line_lower="${line,,}"

	# Save records containing the search term, ignoring case.
	if [[ "$line_lower" == *"$term_lower"* ]]; then
		if ! printf '%s\n' "$line" >>"$findings_file"; then
			printf 'ERROR: Could not write findings to %s\n' "$findings_file" >&2
			exit 1
		fi

		matches_found=$((matches_found + 1))
	fi
done <"$crawl_results_file"

# Report the number of matching records.
printf 'Matching records: %s\n' "$matches_found"
printf 'Findings saved to: %s\n' "$findings_file"

if ((matches_found == 0)); then
	printf 'No records matched: %s\n' "$find_term"
fi

if ! bash "$SCRIPT_DIR/scripts/evidence_report.sh" \
	--input "$crawl_results_file" \
	--term "$find_term" \
	--output-dir "$run_dir"; then
	printf 'ERROR: Evidence report generation failed.\n' >&2
	exit 1
fi
