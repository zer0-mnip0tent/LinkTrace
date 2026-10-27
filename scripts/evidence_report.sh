#!/usr/bin/env bash

# LinkTrace Evidence Report Generator
#
# Reads Katana JSONL output and produces:
#   verified-links.jsonl   Matching HTML anchor links with source pages
#   response-matches.jsonl Response bodies containing the search term
#   evidence-results.jsonl Combined, deduplicated results
#   evidence-results.csv   Spreadsheet-friendly results
#   evidence-report.md     Human-readable report

set -o pipefail

usage() {
	cat <<'EOF'
Usage:
  bash scripts/evidence_report.sh \
    --input crawl.jsonl \
    --term github.com \
    --output-dir results/

Options:
  --input FILE       Katana JSONL input
  --term TEXT        Text or domain to search for
  --output-dir DIR   Directory for the generated reports
EOF
}

input_file=""
term=""
output_dir=""

# Parse command-line arguments.
while (($# > 0)); do
	case "$1" in
	--input)
		if (($# < 2)); then
			printf 'ERROR: Missing value for --input.\n' >&2
			exit 2
		fi
		input_file="$2"
		shift 2
		;;

	--term)
		if (($# < 2)); then
			printf 'ERROR: Missing value for --term.\n' >&2
			exit 2
		fi
		term="$2"
		shift 2
		;;

	--output-dir)
		if (($# < 2)); then
			printf 'ERROR: Missing value for --output-dir.\n' >&2
			exit 2
		fi
		output_dir="$2"
		shift 2
		;;

	--help)
		usage
		exit 0
		;;

	*)
		printf 'ERROR: Unknown option: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
done

# Validate the arguments.
if [[ -z "$input_file" || -z "$term" || -z "$output_dir" ]]; then
	printf 'ERROR: --input, --term and --output-dir are required.\n' >&2
	usage >&2
	exit 2
fi

if [[ ! -f "$input_file" || ! -r "$input_file" ]]; then
	printf 'ERROR: Input file is missing or unreadable: %s\n' \
		"$input_file" >&2
	exit 1
fi

# jq parses JSON reliably; Bash string matching alone cannot safely
# distinguish individual JSON fields.
if ! command -v jq >/dev/null 2>&1; then
	printf 'ERROR: jq is required. Install it with: sudo apt install jq\n' >&2
	exit 1
fi

if ! mkdir -p -- "$output_dir"; then
	printf 'ERROR: Could not create output directory: %s\n' \
		"$output_dir" >&2
	exit 1
fi

# Define output paths. These are separate from the existing findings.jsonl.
links_file="$output_dir/verified-links.jsonl"
body_file="$output_dir/response-matches.jsonl"
all_file="$output_dir/evidence-results.jsonl"
csv_file="$output_dir/evidence-results.csv"
report_file="$output_dir/evidence-report.md"

# Use temporary files so a failed JSON parsing operation does not leave
# partially generated report files.
tmp_dir="$(mktemp -d "$output_dir/.evidence.XXXXXX")" || {
	printf 'ERROR: Could not create temporary working directory.\n' >&2
	exit 1
}
trap 'rm -rf -- "$tmp_dir"' EXIT

# -------------------------------------------------------------------
# 1. Find actual anchor-link records whose destination matches the term.
# -------------------------------------------------------------------

if ! jq -c --arg needle "$term" '
    select(
        (
            ((.request.endpoint // "") |
                if type == "string" then
                    (ascii_downcase | contains($needle | ascii_downcase))
                else
                    false
                end)
        )
        and (((.request.tag // "") | ascii_downcase) == "a")
        and (((.request.attribute // "") | ascii_downcase) == "href")
    )
    | {
        match_type: "anchor_link",
        term: $needle,
        destination: (.request.endpoint // ""),
        source_page: (.request.source // ""),
        tag: (.request.tag // ""),
        attribute: (.request.attribute // ""),
        status_code: (.response.status_code // null)
    }
' "$input_file" >"$tmp_dir/links.raw"; then
	printf 'ERROR: Could not parse Katana JSONL for link matches.\n' >&2
	exit 1
fi

# Deduplicate the same destination from the same source page.
if ! jq -s 'unique_by([.source_page, .destination])[]' \
	"$tmp_dir/links.raw" >"$links_file"; then
	printf 'ERROR: Could not deduplicate link matches.\n' >&2
	exit 1
fi

# -------------------------------------------------------------------
# 2. Find response bodies containing the search term.
# -------------------------------------------------------------------

if ! jq -c --arg needle "$term" '
    select(
        ((.response.body // "") |
            if type == "string" then
                (ascii_downcase | contains($needle | ascii_downcase))
            else
                false
            end)
    )
    | {
        match_type: "response_body",
        term: $needle,
        source_page: (.request.endpoint // ""),
        destination: null,
        matched_field: "response.body",
        status_code: (.response.status_code // null)
    }
' "$input_file" >"$tmp_dir/body.raw"; then
	printf 'ERROR: Could not parse Katana JSONL for body matches.\n' >&2
	exit 1
fi

# Keep one body-match record per source page.
if ! jq -s 'unique_by(.source_page)[]' \
	"$tmp_dir/body.raw" >"$body_file"; then
	printf 'ERROR: Could not deduplicate response-body matches.\n' >&2
	exit 1
fi

# -------------------------------------------------------------------
# 3. Combine both categories.
# -------------------------------------------------------------------

if ! cat -- "$links_file" "$body_file" >"$tmp_dir/all.raw"; then
	printf 'ERROR: Could not combine evidence records.\n' >&2
	exit 1
fi

if ! jq -s 'sort_by([.match_type, .source_page, (.destination // "")])[]' \
	"$tmp_dir/all.raw" >"$all_file"; then
	printf 'ERROR: Could not sort combined evidence records.\n' >&2
	exit 1
fi

link_count="$(wc -l <"$links_file")"
body_count="$(wc -l <"$body_file")"
total_count="$(wc -l <"$all_file")"

# -------------------------------------------------------------------
# 4. Export a CSV report.
# -------------------------------------------------------------------

if ! {
	printf '%s\n' \
		'"match_type","term","source_page","destination","matched_field","status_code","tag","attribute"'

	jq -r '
        [
            .match_type,
            .term,
            .source_page,
            (.destination // ""),
            (.matched_field // ""),
            (.status_code // ""),
            (.tag // ""),
            (.attribute // "")
        ] | @csv
    ' "$all_file"
} >"$csv_file"; then
	printf 'ERROR: Could not write CSV report.\n' >&2
	exit 1
fi

# -------------------------------------------------------------------
# 5. Generate a human-readable Markdown report.
# -------------------------------------------------------------------

if ! {
	printf '# LinkTrace Evidence Report\n\n'
	printf -- '- Search term: `%s`\n' "$term"
	printf -- '- Input: `%s`\n' "$input_file"
	printf -- '- Matching anchor-link records: %s\n' "$link_count"
	printf -- '- Response-body matches: %s\n' "$body_count"
	printf -- '- Total records: %s\n\n' "$total_count"

	printf '## Confirmed anchor-link records\n\n'

	if ((link_count == 0)); then
		printf 'No matching anchor-link records were found.\n\n'
	else
		jq -r -s '.[0:50][] |
            "### " + .destination +
            "\n\n- Source page: " + (.source_page // "Unknown") +
            "\n- HTTP status: " + ((.status_code // "Unknown") | tostring) +
            "\n"
        ' "$links_file"

		if ((link_count > 50)); then
			printf '\nShowing the first 50 records. See `verified-links.jsonl` for all records.\n\n'
		fi
	fi

	printf '## Response-body matches\n\n'

	if ((body_count == 0)); then
		printf 'No matching response-body records were found.\n\n'
	else
		jq -r -s '.[0:50][] |
            "- Page: " + (.source_page // "Unknown") +
            "\n  HTTP status: " + ((.status_code // "Unknown") | tostring) +
            "\n"
        ' "$body_file"

		if ((body_count > 50)); then
			printf '\nShowing the first 50 records. See `response-matches.jsonl` for all records.\n\n'
		fi
	fi

	printf '\n## Interpretation\n\n'
	printf '%s\n' \
		'Anchor-link records are based on Katana metadata identifying an HTML `a` element and its `href` attribute.' \
		'Response-body matches indicate that the term occurs in the captured response body. They may overlap with link matches and are not necessarily plain-text mentions.'
} >"$report_file"; then
	printf 'ERROR: Could not write Markdown report.\n' >&2
	exit 1
fi

# Display a concise summary.
printf '\n========== EVIDENCE REPORT COMPLETE ==========\n'
printf 'Search term: %s\n' "$term"
printf 'Matching anchor-link records: %s\n' "$link_count"
printf 'Response-body matches: %s\n' "$body_count"
printf 'Total records: %s\n' "$total_count"
printf '\nCreated files:\n'
printf '  %s\n' "$links_file"
printf '  %s\n' "$body_file"
printf '  %s\n' "$all_file"
printf '  %s\n' "$csv_file"
printf '  %s\n' "$report_file"
