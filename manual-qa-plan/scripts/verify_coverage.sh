#!/usr/bin/env bash
#
# verify_coverage.sh <files-list> <document>
#
# Reports every changed path the document never mentions. This is the check the skill's step 5
# demands: "check by diffing the two lists, not by impression".
#
# <files-list> is files.md from collect_changes.sh, or any file with one path per line
#              (leading "- " and "M/A/D/R" status columns are tolerated).
# <document>   is the plan document.
#
# Prefer the authoritative list over files.md if the two disagree in length:
#
#     git diff --name-only <BASE>..<HEAD> > /tmp/paths.txt
#     verify_coverage.sh /tmp/paths.txt <document>
#
# files.md is a rendered summary and may fold entries; the diff never does. The count this script
# prints is the count it actually checked — compare it against `git diff --name-only | wc -l` before
# trusting a pass.
#
# A path counts as covered if the document contains it verbatim, or contains its basename. The
# basename fallback exists because a document legitimately writes `ProjectDao.php` in prose after
# giving the full path once. It is deliberately generous: this check is for catching whole files
# that were forgotten, not for auditing how each one is referred to.
#
# It cannot see through a glob. `lib/View/templates/**` in the document does NOT cover the files
# beneath it, and that is the intended behaviour — a glob in a coverage table reads as complete
# while hiding everything under it. Enumerate instead.
#
# Exit status: 0 when every path is covered, 1 when any is missing, 2 on a usage error.

set -uo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $(basename "$0") <files-list> <document>" >&2
    exit 2
fi

FILES=$1
DOC=$2

for f in "$FILES" "$DOC"; do
    if [ ! -r "$f" ]; then
        echo "cannot read: $f" >&2
        exit 2
    fi
done

total=0
missing=0
missing_list=$(mktemp)
trap 'rm -f "$missing_list"' EXIT

# Strip markdown list markers and git status columns, drop blanks, headings and section markers.
while IFS= read -r path; do
    path=${path#- }
    path=$(printf '%s' "$path" | sed -E 's/^[MADRCU][0-9]*[[:space:]]+//')
    path=$(printf '%s' "$path" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')

    case "$path" in
        ''|'#'*|'-'*|'|'*|'```'*|'>'*) continue ;;
    esac

    # a path has no spaces in it; prose lines that survived the strips do
    case "$path" in
        *' '*) continue ;;
    esac

    total=$((total + 1))

    if grep -qF -- "$path" "$DOC"; then
        continue
    fi

    if grep -qF -- "$(basename "$path")" "$DOC"; then
        continue
    fi

    missing=$((missing + 1))
    printf '%s\n' "$path" >> "$missing_list"
done < "$FILES"

echo "paths checked: $total"
echo "paths missing: $missing"

if [ "$missing" -gt 0 ]; then
    echo
    echo "Not mentioned anywhere in the document:"
    sed 's/^/  /' "$missing_list"
    echo
    echo "Each needs a case, a 'not manually testable' row with its reason, or an open question."
    echo "A glob covering them does not count."
    exit 1
fi

echo "every changed path is accounted for"
exit 0
