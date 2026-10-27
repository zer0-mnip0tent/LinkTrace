#!/bin/bash

find_pd_tool() {
	local tool="$1"
	local candidate
	local path
	local help_text
	local -a candidates

	case "$tool" in
	subfinder) candidates=(subfinder) ;;
	httpx) candidates=(httpx-toolkit httpx) ;;
	katana) candidates=(katana) ;;
	*) return 1 ;;
	esac

	for candidate in "${candidates[@]}"; do
		path="$(type -P "$candidate")" || continue
		help_text="$("$path" -h 2>&1 || true)"

		case "$tool" in
		subfinder)
			grep -Fqi 'subdomain discovery tool' <<<"$help_text" || continue
			;;
		httpx)
			grep -Fqi 'multi-purpose HTTP toolkit' <<<"$help_text" || continue
			;;
		katana)
			grep -Fqi 'fast crawler' <<<"$help_text" || continue
			;;
		esac

		printf '%s\n' "$path"
		return 0
	done

	return 1
}

check_dependencies() {
	local tool
	local path
	local missing=0

	for tool in subfinder httpx katana; do
		if path="$(find_pd_tool "$tool")"; then
			printf '[OK] %-10s %s\n' "$tool" "$path"
		else
			printf '[MISSING/INVALID] %s\n' "$tool" >&2
			missing=1
		fi
	done

	if ((missing)); then
		printf '\nERROR: Required dependencies are unavailable or failed verification.\n' >&2
		printf 'Check the official installation instructions:\n' >&2
		printf '  https://github.com/projectdiscovery/subfinder\n' >&2
		printf '  https://github.com/projectdiscovery/httpx\n' >&2
		printf '  https://github.com/projectdiscovery/katana\n' >&2
		return 1
	fi

	printf '\nAll dependency checks passed.\n'
	return 0
}
