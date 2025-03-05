#!/bin/bash
# shellcheck disable=SC2086
# NOTE: Ignore violations as 'echo "name=foo::bar" >> $GITHUB_OUTPUT'.
set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

export REVIEWDOG_GITHUB_API_TOKEN="${INPUT_GITHUB_TOKEN:?}"

# Avoid 'fatal: detected dubious ownership in repository'
git config --global --add safe.directory /github/workspace

# Get changed files
echo '::group::🐶 Get changed files'
# The command is necessary to get changed files.
# TODO Fetch only the target branch
git fetch --prune --unshallow --no-tags

SQL_FILE_PATTERN="${FILE_PATTERN:?}"
SOURCE_REFERENCE="origin/${GITHUB_PULL_REQUEST_BASE_REF:?}"
changed_files=$(git diff --name-only --no-color "$SOURCE_REFERENCE" "HEAD" -- "${SQLFLUFF_PATHS:?}" |
	grep -e "${SQL_FILE_PATTERN:?}" |
	xargs -I% bash -c 'if [[ -f "%" ]] ; then echo "%"; fi' || :)
echo "Changed files:"
echo "$changed_files"
# Halt the job
if [[ ${changed_files} == "" ]]; then
	echo "There is no changed files. The action doesn't scan files."
	echo "name=sqlfluff-exit-code::0" >>$GITHUB_OUTPUT
	echo "name=reviewdog-return-code::0" >>$GITHUB_OUTPUT
	exit 0
fi
echo '::endgroup::'

# Install sqlfluff
echo '::group::🐶 Installing sqlfluff ... https://github.com/sqlfluff/sqlfluff'
pip install --no-cache-dir -r "${SCRIPT_DIR}/requirements/requirements.txt" --use-deprecated=legacy-resolver
# Make sure the version of sqlfluff
sqlfluff --version
echo '::endgroup::'

# Install extra python modules
echo '::group:: Installing extra python modules'
if [[ "x${EXTRA_REQUIREMENTS_TXT}" != "x" ]]; then
	pip install --no-cache-dir -r "${EXTRA_REQUIREMENTS_TXT}" --use-deprecated=legacy-resolver
	# Make sure the installed modules
	pip list
fi
echo '::endgroup::'

# Install dbt packages
echo '::group:: Installing dbt packages'
if [[ -f "${INPUT_WORKING_DIRECTORY}/packages.yml" ]]; then
	default_dir="$(pwd)"
	cd "$INPUT_WORKING_DIRECTORY"
	dbt deps --profiles-dir "${SCRIPT_DIR}/resources/dummy_profiles"
	cd "$default_dir"
fi
echo '::endgroup::'

# Lint changed files if the mode is lint
if [[ ${SQLFLUFF_COMMAND:?} == "lint" ]]; then
	echo '::group:: Running sqlfluff 🐶 ...'
	# Allow failures now, as reviewdog handles them
	set +Eeuo pipefail
	lint_results="sqlfluff-lint.json"
	# shellcheck disable=SC2086,SC2046
	sqlfluff lint \
		--format json \
		--nocolor \
		$(if [[ "x${SQLFLUFF_CONFIG}" != "x" ]]; then echo "--config ${SQLFLUFF_CONFIG}"; fi) \
		$(if [[ "x${SQLFLUFF_DIALECT}" != "x" ]]; then echo "--dialect ${SQLFLUFF_DIALECT}"; fi) \
		$(if [[ "x${SQLFLUFF_PROCESSES}" != "x" ]]; then echo "--processes ${SQLFLUFF_PROCESSES}"; fi) \
		$(if [[ "x${SQLFLUFF_RULES}" != "x" ]]; then echo "--rules ${SQLFLUFF_RULES}"; fi) \
		$(if [[ "x${SQLFLUFF_EXCLUDE_RULES}" != "x" ]]; then echo "--exclude-rules ${SQLFLUFF_EXCLUDE_RULES}"; fi) \
		$(if [[ "x${SQLFLUFF_TEMPLATER}" != "x" ]]; then echo "--templater ${SQLFLUFF_TEMPLATER}"; fi) \
		$(if [[ "x${SQLFLUFF_DISABLE_NOQA}" != "x" ]]; then echo "--disable-noqa ${SQLFLUFF_DISABLE_NOQA}"; fi) \
		$(if [[ "x${SQLFLUFF_DIALECT}" != "x" ]]; then echo "--dialect ${SQLFLUFF_DIALECT}"; fi) \
		$changed_files |
		tee "$lint_results"
	sqlfluff_exit_code=$?

	echo "name=sqlfluff-results::$(cat <"$lint_results" | jq -r -c '.')" >>$GITHUB_OUTPUT # Convert to a single line
	echo "name=sqlfluff-exit-code::${sqlfluff_exit_code}" >>$GITHUB_OUTPUT

	set -Eeuo pipefail
	echo '::endgroup::'

	echo '::group:: Running reviewdog 🐶 ...'
	# Allow failures now, as reviewdog handles them
	set +Eeuo pipefail

	lint_results_rdjson="sqlfluff-lint.rdjson"
	cat <"$lint_results" |
		jq -r -f "${SCRIPT_DIR}/to-rdjson.jq" |
		tee >"$lint_results_rdjson"

	cat <"$lint_results_rdjson" |
		reviewdog -f=rdjson \
			-name="sqlfluff-lint" \
			-reporter="${REVIEWDOG_REPORTER}" \
			-filter-mode="${REVIEWDOG_FILTER_MODE}" \
			-fail-on-error="${REVIEWDOG_FAIL_ON_ERROR}" \
			-level="${REVIEWDOG_LEVEL}"
	reviewdog_return_code="${PIPESTATUS[1]}"

	echo "name=sqlfluff-results-rdjson::$(cat <"$lint_results_rdjson" | jq -r -c '.')" >>$GITHUB_OUTPUT # Convert to a single line
	echo "name=reviewdog-return-code::${reviewdog_return_code}" >>$GITHUB_OUTPUT

	set -Eeuo pipefail
	echo '::endgroup::'

	exit $sqlfluff_exit_code
# END OF lint

# Format changed files if the mode is fix
elif [[ ${SQLFLUFF_COMMAND} == "fix" ]]; then
	echo '::group:: Running sqlfluff fix 🐶 ...'
	# Allow failures now, as reviewdog handles them
	set +Eeuo pipefail
	
	# First, make a copy of the original files for comparison
	temp_dir=$(mktemp -d)
	for file in $changed_files; do
		mkdir -p "$temp_dir/$(dirname "$file")"
		cp "$file" "$temp_dir/$file"
	done
	
	# Run sqlfluff fix
	# shellcheck disable=SC2086,SC2046
	sqlfluff fix \
		--nocolor \
		$(if [[ "x${SQLFLUFF_CONFIG}" != "x" ]]; then echo "--config ${SQLFLUFF_CONFIG}"; fi) \
		$(if [[ "x${SQLFLUFF_DIALECT}" != "x" ]]; then echo "--dialect ${SQLFLUFF_DIALECT}"; fi) \
		$(if [[ "x${SQLFLUFF_PROCESSES}" != "x" ]]; then echo "--processes ${SQLFLUFF_PROCESSES}"; fi) \
		$(if [[ "x${SQLFLUFF_RULES}" != "x" ]]; then echo "--rules ${SQLFLUFF_RULES}"; fi) \
		$(if [[ "x${SQLFLUFF_EXCLUDE_RULES}" != "x" ]]; then echo "--exclude-rules ${SQLFLUFF_EXCLUDE_RULES}"; fi) \
		$(if [[ "x${SQLFLUFF_TEMPLATER}" != "x" ]]; then echo "--templater ${SQLFLUFF_TEMPLATER}"; fi) \
		$(if [[ "x${SQLFLUFF_DISABLE_NOQA}" != "x" ]]; then echo "--disable-noqa ${SQLFLUFF_DISABLE_NOQA}"; fi) \
		$(if [[ "x${SQLFLUFF_DIALECT}" != "x" ]]; then echo "--dialect ${SQLFLUFF_DIALECT}"; fi) \
		$changed_files
	sqlfluff_exit_code=$?
	echo "name=sqlfluff-exit-code::${sqlfluff_exit_code}" >>$GITHUB_OUTPUT

	set -Eeuo pipefail
	echo '::endgroup::'

	# Generate diff for reviewdog
	echo '::group:: Running reviewdog for fix suggestions 🐶 ...'
	# Allow failures now, as reviewdog handles them
	set +Eeuo pipefail

	# Create a diff file for each changed file
	diff_file=$(mktemp)
	for file in $changed_files; do
		if [[ -f "$temp_dir/$file" && -f "$file" ]]; then
			# Create a unified diff
			diff -u "$temp_dir/$file" "$file" | sed "s|$temp_dir/||" >> "$diff_file" || true
		fi
	done
	
	# Check if we have any diffs
	if [[ -s "$diff_file" ]]; then
		# Send the diff to reviewdog
		cat "$diff_file" | reviewdog \
			-name="sqlfluff-fix" \
			-f=diff \
			-f.diff.strip=1 \
			-reporter="${REVIEWDOG_REPORTER}" \
			-filter-mode="${REVIEWDOG_FILTER_MODE}" \
			-fail-on-error="${REVIEWDOG_FAIL_ON_ERROR}" \
			-level="${REVIEWDOG_LEVEL}"
	else
		echo "No changes were made by sqlfluff fix"
	fi
	
	# Clean up
	rm -rf "$temp_dir"
	rm -f "$diff_file"
	
	set -Eeuo pipefail
	echo '::endgroup::'
	
	# Run lint after fix to report remaining issues
	echo '::group:: Running sqlfluff lint after fix to report remaining issues 🐶 ...'
	# Allow failures now, as reviewdog handles them
	set +Eeuo pipefail
	
	# Run a separate lint command to find unfixable issues
	lint_results="sqlfluff-lint-after-fix.json"
	
	# Run sqlfluff lint with the same parameters as the original fix command
	# but add --no-jinja to analyze the raw SQL files rather than compiled templates
	# shellcheck disable=SC2086,SC2046
	sqlfluff lint \
		--format json \
		--nocolor \
		--no-jinja \
		$(if [[ "x${SQLFLUFF_CONFIG}" != "x" ]]; then echo "--config ${SQLFLUFF_CONFIG}"; fi) \
		$(if [[ "x${SQLFLUFF_DIALECT}" != "x" ]]; then echo "--dialect ${SQLFLUFF_DIALECT}"; fi) \
		$(if [[ "x${SQLFLUFF_PROCESSES}" != "x" ]]; then echo "--processes 1"; fi) \
		$(if [[ "x${SQLFLUFF_RULES}" != "x" ]]; then echo "--rules ${SQLFLUFF_RULES}"; fi) \
		$(if [[ "x${SQLFLUFF_EXCLUDE_RULES}" != "x" ]]; then echo "--exclude-rules ${SQLFLUFF_EXCLUDE_RULES}"; fi) \
		$(if [[ "x${SQLFLUFF_DISABLE_NOQA}" != "x" ]]; then echo "--disable-noqa ${SQLFLUFF_DISABLE_NOQA}"; fi) \
		$(if [[ "x${SQLFLUFF_DIALECT}" != "x" ]]; then echo "--dialect ${SQLFLUFF_DIALECT}"; fi) \
		$changed_files > "$lint_results" || true
	
	# Check if we have valid JSON output
	if jq empty "$lint_results" 2>/dev/null; then
		echo "Successfully generated lint results after fix"
		
		# Convert to reviewdog format
		lint_results_rdjson="sqlfluff-lint-after-fix.rdjson"
		cat "$lint_results" | jq -r -f "${SCRIPT_DIR}/to-rdjson.jq" > "$lint_results_rdjson" || true
		
		# Send to reviewdog if we have valid rdjson
		if jq empty "$lint_results_rdjson" 2>/dev/null; then
			cat "$lint_results_rdjson" | reviewdog \
				-f=rdjson \
				-name="sqlfluff-remaining-issues" \
				-reporter="${REVIEWDOG_REPORTER}" \
				-filter-mode="${REVIEWDOG_FILTER_MODE}" \
				-fail-on-error="${REVIEWDOG_FAIL_ON_ERROR}" \
				-level="${REVIEWDOG_LEVEL}" || true
			
			echo "name=sqlfluff-remaining-issues::$(cat "$lint_results" | jq -r -c '.')" >>$GITHUB_OUTPUT
		else
			echo "Warning: Failed to convert lint results to valid rdjson format"
			echo "name=sqlfluff-remaining-issues::{}" >>$GITHUB_OUTPUT
		fi
	else
		echo "Warning: Failed to generate valid lint results after fix"
		echo "name=sqlfluff-remaining-issues::{}" >>$GITHUB_OUTPUT
	fi
	
	set -Eeuo pipefail
	echo '::endgroup::'

	exit $sqlfluff_exit_code
# END OF fix
else
	echo 'ERROR: SQLFLUFF_COMMAND must be one of lint and fix'
	exit 1
fi
