#!/bin/bash
set -o pipefail -e
# shellcheck disable=SC1090,SC2034,SC1017
true

MODULE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

source "$MODULE_DIR/ci_scripts/helpers.sh"
source "$MODULE_DIR/ci_scripts/icons.sh"

NOW="$(date +'%B %d, %Y')"

V_SUGGEST="0.1.0" # This is suggested in case VERSION file or user supplied version via -v is missing
VER_FILE="package.json"
GIT_MSG=""
REL_NOTE=""
REL_PREFIX="release-"
COMMIT_MSG_PREFIX="chore: " # Commit msg prefix for the file changes this script makes
PUSH_DEST="origin"
PARENT_PROJECTS_DIR=()

JSON_FILES=()

#### Initiate Script ###########################

main() {
    # Process and prepare
    process-arguments "$@"
    check-commits-exist
    process-version
    echo -e "\n${S_LIGHT}Checking git branch, tags and commits..."
    check-branch-notexist
    check-tag-exists
    #check_parent_project_files_changed
    echo -e "\n${S_LIGHT}----------File Updates----------------"

    # Update files
    do-update-parent-project
    # do-packagefile-bump
    # bump-json-files
    # do-versionfile
    # do-changelog
    # do-branch
    # do-commit
    # do-tag
    # do-push

    # echo -e "\n${S_LIGHT}------"
    # echo -ne "\n${I_OK} ${S_NOTICE}"
    # capitalise "$(get-commit-msg)"
    # echo -e "\n${I_END} ${GREEN}Done!\n"
}

# Execute script when it is executed as a script, and when it is brought into the environment with source (so it can be tested)
# shellcheck disable=SC2128
if [[ "$0" = "$BASH_SOURCE" ]]; then
    source "$MODULE_DIR/ci_scripts/styles.sh" # only load when not sourced, for tests to work
    main "$@"
fi
