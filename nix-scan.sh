#!/usr/bin/env bash
# export PATH="${PATH}" placeholder

set -o errexit
set -o nounset
set -o pipefail

function print() {
    printf "%s\n" "${1-}" >&2
}

function warn() {
    printf "%s%s%s\n" "${color_warn-}" "${1-}" "${color_reset-}" >&2
}

function success() {
    printf "%s%s%s\n" "${color_success-}" "${1-}" "${color_reset-}" >&2
}

function array() {
    local string="$1"
    local new_array=()
    local array=()

    # split by either spaces or newlines
    if [[ "${string}" == *$'\n'* ]]; then
        readarray -t new_array <<< "${string}"
    else
        IFS=" " read -r -a new_array <<< "${string}"
    fi

    # remove empty entries
    for item in "${new_array[@]}"; do
        if [[ -n "${item}" ]]; then
            array+=( "${item}" )
        fi
    done

    # return empty if no entries
    if [[ "${#array[@]}" -eq 0 ]]; then
        return
    fi

    printf "%s\n" "${array[@]}"
}

function extract_version() {
    local version_string="$1"

    temp="${version_string%\"}" # removes trailing double quote
    temp="${temp#\"}" # removes leading double quote
    version_string="${temp}"

    local major minor patch
    if pcre2grep "^.*?([0-9]+)\.([0-9]+)\.([0-9]+)$" <<< "$version_string" &> /dev/null; then
        major=$(pcre2grep -o1 "^.*?([0-9]+)\.([0-9]+)\.([0-9]+)$" <<< "$version_string")
        minor=$(pcre2grep -o2 "^.*?([0-9]+)\.([0-9]+)\.([0-9]+)$" <<< "$version_string")
        patch=$(pcre2grep -o3 "^.*?([0-9]+)\.([0-9]+)\.([0-9]+)$" <<< "$version_string")
    elif pcre2grep "^.*?([0-9]+)\.([0-9]+)$" <<< "$version_string" &> /dev/null; then
        major=$(pcre2grep -o1 "^.*?([0-9]+)\.([0-9]+)$" <<< "$version_string")
        minor=$(pcre2grep -o2 "^.*?([0-9]+)\.([0-9]+)$" <<< "$version_string")
        patch="0"
    elif pcre2grep "^.*?([0-9]+)$" <<< "$version_string" &> /dev/null; then
        major=$(pcre2grep -o1 "^.*?([0-9]+)$" <<< "$version_string")
        minor="0"
        patch="0"
    else
        echo "0.0.0"
        return
    fi

    echo "${major}.${minor}.${patch}"
}

function greater_than() {
    local version_a="$1"
    local version_b="$2"

    IFS='.' read -r -a parts_a <<< "$version_a"
    IFS='.' read -r -a parts_b <<< "$version_b"

    for i in 0 1 2; do
        local part_a=${parts_a[i]:-0}
        local part_b=${parts_b[i]:-0}

        if (( part_a > part_b )); then
            return 0
        elif (( part_a < part_b )); then
            return 1
        fi
    done

    return 1
}

# default TERM to linux
if [[ -n "${CI-}" || -z "${TERM-}" ]]; then
    TERM=linux
fi

# set colors
if colors=$(tput -T "${TERM}" colors 2> /dev/null); then
    color_reset=$(tput -T "${TERM}" sgr0)
    if [[ "$colors" -ge 256 ]]; then
        color_warn=$(tput -T "${TERM}" setaf 216)
        color_success=$(tput -T "${TERM}" setaf 117)
    elif [[ "$colors" -ge 8 ]]; then
        color_warn=$(tput -T "${TERM}" setaf 3)
        color_success=$(tput -T "${TERM}" setaf 2)
    fi
fi

if [[ -z "${GITHUB_TOKEN-}" ]]; then
    warn "GITHUB_TOKEN is not set, it's essentially required for higher rate limits"
    exit 1
fi

if [[ -n "${GITHUB_STEP_SUMMARY-}" ]]; then
    echo "## <img src=\"https://brand.nixos.org/internals/nixos-logomark-default-gradient-none.svg\" alt=\"NixOS\" width=\"20\"> Nix Scan Report" >> "${GITHUB_STEP_SUMMARY}"
fi

# get args
ARGS=()
if [[ "$#" -gt 0 ]]; then
    ARGS+=( "${@}" )
fi
if [[ -n "${ENV_ARGS-}" ]]; then
    readarray -t ENV_ARGS < <(array "${ENV_ARGS-}")
    ARGS+=( "${ENV_ARGS[@]}" )
fi

readarray -t urls < <(
    nix derivation show -r "${ARGS[@]}" |
        jq -r '.[] | select(.env.urls) | .env.urls | select(contains("github.com"))' |
        uniq
)

code=0
re="^(https|git)(:\/\/|@)([^\/:]+)[\/:]([^\/:]+)\/([^\/:]+)\/.+\/(.*)\.tar\..+$"

for url in "${urls[@]}"; do
    if [[ $url =~ $re ]]; then
        user=${BASH_REMATCH[4]}
        repo=${BASH_REMATCH[5]}
        version=$(extract_version "${BASH_REMATCH[6]}")
        vulnerable="false"

        if [[ -n "${CI-}" ]]; then
            print "::group::checking ${user}/${repo} (v${version})"
        else
            print "checking ${user}/${repo} (v${version})"
        fi

        readarray -t vulns < <(curl -L \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_TOKEN-}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/${user}/${repo}/security-advisories" 2> /dev/null |
            jq -c '.[]'
        )

        for vuln in "${vulns[@]}"; do
            patched="true"

            readarray -t patched_versions < <(echo "${vuln}" | jq -c '.vulnerabilities[].patched_versions')
            for patched_version in "${patched_versions[@]}"; do
                patched_version=$(extract_version "${patched_version}")
                if greater_than "$patched_version" "$version"; then
                    patched="false"
                    vulnerable="true"
                    code=1
                fi
            done

            if [[ $patched == "false" ]]; then
                if [[ -n "${GITHUB_STEP_SUMMARY-}" ]]; then
                    {
                    echo "### $(echo "${vuln}" | jq -r '.ghsa_id')"
                    printf "%s\n\n" "$(echo "${vuln}" | jq -r '.description')"
                    echo "---"
                    } >> "${GITHUB_STEP_SUMMARY}"
                fi

                warn "$(echo "${vuln}" | jq -r '.ghsa_id'): $(echo "${vuln}" | jq -r '.summary')"
            else
                print "$(echo "${vuln}" | jq -r '.ghsa_id'): $(echo "${vuln}" | jq -r '.summary')"
            fi
        done

        if [[ -n "${CI-}" ]]; then
            print "::endgroup::"
        fi

        if [[ $vulnerable == "true" ]]; then
            warn "${user}/${repo} (v${version})"
        else
            success "${user}/${repo} (v${version})"
        fi

        print ""
    fi
done

if [[ $code -eq 0 ]]; then
    success "no vulnerabilities found"

    if [[ -n "${GITHUB_STEP_SUMMARY-}" ]]; then
        echo "### No vulnerabilities found" >> "${GITHUB_STEP_SUMMARY}"
    fi
else
    warn "vulnerabilities found"
fi

exit $code