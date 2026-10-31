#!/usr/bin/env bash
# Build tmux from any tag, branch or commit of github.com/tmux/tmux.
#
# The Linux matrix builds each table release through its pinned path. This
# script is for the rest: a dispatch that debugs a ref outside the table.
#
#   build-tmux.sh --resolve <ref>   print commit=<40-hex> for the ref
#   build-tmux.sh --ref <ref>       build the ref, print binary=, commit=, version=
#
# A ref is a tag, a branch, or a full 40-hex commit. It is resolved to a commit
# first, and the build is cached under that commit, never under the name.
set -euo pipefail

readonly TMUX_REPOSITORY="${LIBTMUX_TMUX_REPOSITORY:-https://github.com/tmux/tmux.git}"
BUILD_ROOT="${LIBTMUX_TMUX_BUILD_ROOT:-build/tmux-ref}"
readonly BUILD_ROOT

usage() {
    echo "usage: build-tmux.sh --resolve <tag|branch|40-hex commit>" >&2
    echo "       build-tmux.sh --ref <tag|branch|40-hex commit>" >&2
    exit 2
}

[[ $# -eq 2 && ( "$1" == --resolve || "$1" == --ref ) ]] || usage
readonly MODE="${1#--}"
readonly REF="$2"

if [[ ! "${REF}" =~ ^[A-Za-z0-9._/-]{1,64}$ \
    || "${REF}" == -* || "${REF}" == *..* || "${REF}" == */ || "${REF}" == *.lock ]]; then
    echo "not a usable tmux ref: ${REF}" >&2
    exit 1
fi
if [[ "${REF}" =~ ^[0-9a-f]{7,39}$ ]]; then
    echo "abbreviated commit: give the full 40-hex SHA for ${REF}" >&2
    exit 1
fi

# A tag is peeled to its commit and wins over a branch of the same name, as it
# does for a clone.
resolve_commit() {
    if [[ "${REF}" =~ ^[0-9a-f]{40}$ ]]; then
        printf '%s\n' "${REF}"
        return 0
    fi
    local listing name commit
    listing="$(git ls-remote "${TMUX_REPOSITORY}" \
        "refs/tags/${REF}^{}" "refs/tags/${REF}" "refs/heads/${REF}")" || return 1
    for name in "refs/tags/${REF}^{}" "refs/tags/${REF}" "refs/heads/${REF}"; do
        commit="$(awk -v name="${name}" '$2 == name {print $1; exit}' <<<"${listing}")"
        if [[ "${commit}" =~ ^[0-9a-f]{40}$ ]]; then
            printf '%s\n' "${commit}"
            return 0
        fi
    done
    echo "${REF} is not a tag, a branch or a full commit of ${TMUX_REPOSITORY}" >&2
    return 1
}

COMMIT="$(resolve_commit)"
readonly COMMIT
if [[ "${MODE}" == resolve ]]; then
    printf 'commit=%s\n' "${COMMIT}"
    exit 0
fi

readonly SOURCE="${BUILD_ROOT}/sources/ref-${COMMIT}"
readonly INSTALL="${BUILD_ROOT}/installs/ref-${COMMIT}"
readonly BINARY="${INSTALL}/bin/tmux"

report() {
    printf 'binary=%s\n' "$(realpath "${BINARY}")"
    printf 'commit=%s\n' "${COMMIT}"
    printf 'version=%s\n' "$(<"${INSTALL}/version")"
}

# A cached build counts only if it still reports the version recorded when it
# was built, from the commit it is named for.
if [[ -x "${BINARY}" && -f "${INSTALL}/version" && -f "${INSTALL}/source-commit" \
    && "$(<"${INSTALL}/source-commit")" == "${COMMIT}" \
    && "$("${BINARY}" -V | sed -n 's/^tmux //p')" == "$(<"${INSTALL}/version")" ]]; then
    report
    exit 0
fi
if [[ -e "${INSTALL}" ]]; then
    echo "cache validation failed; rebuilding ${COMMIT}" >&2
fi

mkdir -p "${SOURCE}"
if [[ "$(git -C "${SOURCE}" rev-parse --verify --quiet HEAD 2>/dev/null || true)" != "${COMMIT}" ]]; then
    git -C "${SOURCE}" init --quiet
    git -C "${SOURCE}" fetch --quiet --depth 1 "${TMUX_REPOSITORY}" "${COMMIT}"
    git -C "${SOURCE}" checkout --quiet --detach FETCH_HEAD
fi
if [[ "$(git -C "${SOURCE}" rev-parse HEAD)" != "${COMMIT}" ]]; then
    echo "tmux source is not at ${COMMIT}" >&2
    exit 1
fi

mkdir -p "${INSTALL}"
(
    cd "${SOURCE}"
    sh autogen.sh
    ./configure --prefix="$(realpath "${INSTALL}")"
    make --jobs="${LIBTMUX_BUILD_JOBS:-$(nproc)}"
    make install
) >&2

[[ -x "${BINARY}" ]] || { echo "tmux build did not produce ${BINARY}" >&2; exit 1; }
VERSION="$("${BINARY}" -V | sed -n 's/^tmux //p')"
[[ -n "${VERSION}" ]] || { echo "tmux build reports no version" >&2; exit 1; }
printf '%s\n' "${VERSION}" > "${INSTALL}/version"
printf '%s\n' "${COMMIT}" > "${INSTALL}/source-commit"
report
