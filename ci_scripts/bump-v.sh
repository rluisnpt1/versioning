#!/bin/bash

# shellcheck disable=SC2288
true
MODULE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
NOW="$(date +'%B %d, %Y')"
V_NEW_TAG="0.1.0" # This is suggested in case VERSION file or user supplied version via -v is missing
V_PREV_TAG=""
PACKAGEJS_VER_FILE="package.json"
GIT_MSG=""
REL_NOTE=""
REL_PREFIX="release-"
COMMIT_MSG_PREFIX="chore: " # Commit msg prefix for the file changes this script makes
PUSH_DEST="origin"
JSON_FILES=()
FLAG_BUMP_MINOR=false

source "$MODULE_DIR/ci_scripts/styles.sh"
source "$MODULE_DIR/ci_scripts/icons.sh"

# Process script options
process-arguments() {
    local OPTIONS OPTIND OPTARG

    # Get positional parameters
    while getopts ":u:p:m:f:hbcl" OPTIONS; do # Note: Adding the first : before the flags takes control of flags and prevents default error msgs.
        case "$OPTIONS" in
        h)
            # Show help
            usage
            exit 0
            ;;
        m)
            REL_NOTE=$OPTARG
            # Custom release note
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Release note: ${S_NORM} '$REL_NOTE'"
            ;;
        u)
            FLAG_BUMP_MINOR=false
            FLAG_BUMP_MINOR=${OPTARG} # Replace default with user input
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Update Minor Version when bumping <${S_NORM}${FLAG_BUMP_MINOR}${S_LIGHT}>"
            ;;
        p)
            FLAG_PUSH=true
            PUSH_DEST=${OPTARG} # Replace default with user input
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Pushing to <${S_NORM}${PUSH_DEST}${S_LIGHT}>, as the last action in this script."
            ;;
        n)
            FLAG_NOCOMMIT=true
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Disable commit after tagging release."
            ;;
        b)
            FLAG_NOBRANCH=true
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Disable committing to new branch."
            ;;
        c)
            FLAG_NOCHANGELOG=true
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Disable updating CHANGELOG.md automatically with new commits since last release tag."
            ;;
        l)
            FLAG_CHANGELOG_PAUSE=true
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Pause enabled for amending CHANGELOG.md"
            ;;
        \?)
            echo -e "\n${I_ERROR}${S_ERROR} Invalid option: ${S_WARN}-$OPTARG" >&2
            echo
            exit 1
            ;;
        :)
            echo -e "\n${I_ERROR}${S_ERROR} Option ${S_WARN}-$OPTARG ${S_ERROR}requires an argument." >&2
            echo
            exit 1
            ;;
        esac
    done
}

GetParentOfFilesChangedInGitCommit() {
    proj_dir_name=("")
    for value in $1; do
        ## get name of first subdirectory
        projectDirRepo="$(cut -d '/' -f 1 <<<"$value")"
        # Add new element at the end of the array
        proj_dir_name="$proj_dir_name $projectDirRepo"
    done
    PARENT_PROJECTS_DIR="$proj_dir_name"
    PARENT_PROJECTS_DIR=$(printf '%s\n' "$PARENT_PROJECTS_DIR" | awk -v RS='[,[:space:]]+' '!a[$0]++{printf "%s%s", $0, RT}')
    PARENT_PROJECTS_DIR="${PARENT_PROJECTS_DIR%,*}"
}

capitalise() {
    echo "$(tr '[:lower:]' '[:upper:]' <<<"${1:0:1}")${1:1}"
}

get-commit-msg() {
    local CMD
    CMD=$([ ! "${V_PREV}" = "${V_NEW}" ] && echo "${V_PREV} ->" || echo "to")
    echo bumped "$CMD" "$V_NEW"
}

# Only tag if tag doesn't already exist
check-tag-exists() {
    TAG_MSG=$(git tag -l "v${V_NEW_TAG}")
    if [ -n "$TAG_MSG" ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error: A release with that tag version number already exists!\n\n$TAG_MSG\n"
        exit 1
    fi
}

#Do checkout no a new branch
do-branch() {
    [ "$FLAG_NOBRANCH" = true ] && return
    V_NEW="$1"
    echo -e "\n${S_NOTICE}Creating new release branch..."

    BRANCH_MSG=$(git branch "${REL_PREFIX}${V_NEW}" 2>&1)
    if [ -z "$BRANCH_MSG" ]; then
        BRANCH_MSG=$(git checkout "${REL_PREFIX}${V_NEW}" 2>&1)
        echo -e "\n${I_OK} ${S_NOTICE}${BRANCH_MSG}"
    else
        echo -e "\n${I_STOP} ${S_ERROR}Error\n$BRANCH_MSG\n"
        exit 1
    fi

    # REL_PREFIX
}

# Stage & commit all files modified by this script
do-commit() {
    local prefix=""
    local message_body=""

    [ "$FLAG_NOCOMMIT" = true ] && return

    if [ ! -z "$1" ]; then
        message_body=$1
    fi

    GIT_MSG+="$(get-commit-msg)"
    echo -e "\n${S_NOTICE}Committing..."

    COMMIT_MSG=$(git commit -m "${COMMIT_MSG_PREFIX}${GIT_MSG}" -m "${message_body}" 2>&1)
    # shellcheck disable=SC2181
    if [ ! "$?" -eq 0 ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error\n$COMMIT_MSG\n"
        git restore . --staged
        git restore .
        exit 1
    else
        echo -e "\n${I_OK} ${S_NOTICE}$COMMIT_MSG"
    fi
}

# Create a Git tag using the SemVar
do-tag() {
    local OLD="$1"
    local V_NEW="$2"
    if [ -z "${REL_NOTE}" ]; then
        # Default release note
        git tag -a "${V_NEW}" -m "Tag to a new version "$OLD" ---> ${V_NEW}."
    else
        # Custom release note
        git tag -a "${V_NEW}" -m "${REL_NOTE}"
    fi
    echo -e "\n${I_OK} ${S_NOTICE}Added GIT tag"
}

# Pushes files + tags to remote repo. Changes are staged by earlier functions
do-push() {
    [ "$FLAG_NOCOMMIT" = true ] && return
    V_NEW="$1"
    if [ "$FLAG_PUSH" = true ]; then
        CONFIRM="Y"
    else
        echo -ne "\n${S_QUESTION}Push tags to <${S_NORM}${PUSH_DEST}${S_QUESTION}>? [${S_NORM}N/y${S_QUESTION}]: "
        read -r CONFIRM
    fi

    case "$CONFIRM" in
    [yY][eE][sS] | [yY])
        echo -e "\n${S_NOTICE}Pushing files + tags to <${S_NORM}${PUSH_DEST}${S_NOTICE}>..."
        PUSH_MSG=$(git push "${PUSH_DEST}" "$V_NEW" 2>&1) # Push new tag
        if [ ! "$PUSH_MSG" -eq 0 ]; then
            echo -e "\n${I_STOP} ${S_WARN}Warning\n$PUSH_MSG"
            # exit 1
        else
            echo -e "\n${I_OK} ${S_NOTICE}$PUSH_MSG"
        fi
        ;;
    esac
}

extract_version_from_json() {
    # NPM environment variables are fetched with cross-platform tool cross-env (overkill to use a dependency, but seems the only way AFAIK to get npm vars)
    local SCRIPT_VER="$1"
    RETURNV=
    for env_var in "${SCRIPT_VER[@]}"; do
        env_var_val=$(eval "echo \$${env_var}" | awk -F: '{ print $2 }' | sed 's/[",]//g' | sed "s/^[ \t]*//")
        RETURNV="$env_var_val"
    done
    RESULT_VER="$RETURNV"
}
updatePackageJsonVersion() {
    local V_NEW_TAG_LOCAL="$1"
    echo "${I_TIME} Updationg to a new version..."
    NPM_MSG=$(npm version "${V_NEW_TAG_LOCAL}" --git-tag-version=false 2>&1)
    # shellcheck disable=SC2181
    if [ ! "$?" -eq 0 ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error updating <package.json> and/or <package-lock.json>.\n\n$NPM_MSG\n"
        git restore . --staged
        git restore .
        exit 1
    else
        git add package.json
        GIT_MSG+="updated package.json "
        if [ -f package-lock.json ]; then
            git add package-lock.json
            GIT_MSG+=",package-lock.json, "
            NOTICE_MSG+=" and <${S_NORM}package-lock.json${S_NOTICE}>"
        fi
        echo -e "\n${I_OK} ${S_NOTICE}Bumped version in ${NOTICE_MSG}. To ${V_NEW_TAG_LOCAL}"
    fi
}

do-package_JSON_file-bump() {
    local V_PREV_TAG_LOCAL="$1"
    local V_NEW_TAG_LOCAL="$2"
    local V_PKG_JSON_DIR="$3"

    NOTICE_MSG="<${S_NORM}package.json${S_NOTICE}>"

    if [ "$V_NEW_TAG_LOCAL" = "$V_PREV_TAG_LOCAL" ]; then
        echo -e "\n${I_WARN}${NOTICE_MSG}${S_WARN} already contains version ${V_NEW_TAG_LOCAL}."
    else
        #IF CONTAINS SUB PROJECT, CHECK IF PARENT IS DIRECTORY
        if [[ -d $V_PKG_JSON_DIR ]]; then

            ## NAVIGATE INTO DIR
            cd "./$V_PKG_JSON_DIR/"
            updatePackageJsonVersion "$V_NEW_TAG_LOCAL"
            # NAVIGATE OUT DIRECTORY
            cd ..
        else
            updatePackageJsonVersion "$V_NEW_TAG_LOCAL"
        fi

    fi
}

do-new-tag-version() {
    local LOCAL_VERSION="$1"
    #replace . with space so can split into an array
    local VERSION_BITS=(${LOCAL_VERSION//./ })
    #get number parts and increase last one by 1
    local V_MAJOR=${VERSION_BITS[0]}
    local V_MINOR=${VERSION_BITS[1]}
    local PATCH=${VERSION_BITS[2]}

    if [ "$FLAG_BUMP_MINOR" = true ]; then
        V_MINOR=$((V_MINOR + 1))
        PATCH=$((0))
    else
        PATCH=$((PATCH + 1))
    fi
    #create new tag
    RESULT_TAG="${V_MAJOR}.${V_MINOR}.${PATCH}"
}

read_version_from_jsonfile() {
    local DIR_NAME=$1
    if [ -z "$DIR_NAME" ]; then
        SCRIPT_VER=$(grep version package.json | head -1)
        PROJ_NAME=$(grep name package.json | head -1)
    else
        SCRIPT_VER=$(cd "$DIR_NAME" && grep version package.json | head -1)
        PROJ_NAME=$(cd "$DIR_NAME" && grep name package.json | head -1)
    fi
}
# Dump git log history to CHANGELOG.md
do-changelog() {
    [ "$FLAG_NOCHANGELOG" = true ] && return
    local COMMITS_MSG LOG_MSG RANGE

    RANGE=$([ "$(git tag -l v"${V_PREV}")" ] && echo "v${V_PREV}...HEAD")
    COMMITS_MSG=$(git log --pretty=format:"- %s" "${RANGE}" 2>&1)
    # shellcheck disable=SC2181
    if [ ! "$?" -eq 0 ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error getting commit history since last version bump for logging to CHANGELOG.\n\n$LOG_MSG\n"
        git restore . --staged
        git restore .
        exit 1
    fi

    [ -f CHANGELOG.md ] && ACTION_MSG="updated" || ACTION_MSG="created"
    # Add info to commit message for later:
    GIT_MSG+="${ACTION_MSG} CHANGELOG.md, "

    # Add heading
    echo "## $V_NEW ($NOW)" >tmpfile

    # Log the bumping commit:
    # - The final commit is done after do-changelog(), so we need to create the log entry for it manually:
    LOG_MSG="${GIT_MSG}$(get-commit-msg)"
    # LOG_MSG="$( capitalise "${LOG_MSG}" )" # Capitalise first letter
    echo "- ${COMMIT_MSG_PREFIX}${LOG_MSG}" >>tmpfile
    # Add previous commits
    [ -n "$COMMITS_MSG" ] && echo "$COMMITS_MSG" >>tmpfile

    echo -en "\n" >>tmpfile

    if [ -f CHANGELOG.md ]; then
        # Append existing log
        cat CHANGELOG.md >>tmpfile
    else
        echo -e "\n${S_WARN}An existing [${S_NORM}CHANGELOG.md${S_WARN}] file was not found. Creating one..."
    fi

    mv tmpfile CHANGELOG.md

    echo -e "\n${I_OK} ${S_NOTICE}$(capitalise "${ACTION_MSG}") [${S_NORM}CHANGELOG.md${S_NOTICE}] file."

    # Optionally pause & allow user to open and edit the file:
    if [ "$FLAG_CHANGELOG_PAUSE" = true ]; then
        echo -en "\n${S_QUESTION}Make adjustments to [${S_NORM}CHANGELOG.md${S_QUESTION}] if required now. Press <enter> to continue."
        read -r
    fi

    # Stage log file, to commit later
    git add CHANGELOG.md
}

#

process_versioning() {
    local dir=$1
    #search and read Package.json within dir
    read_version_from_jsonfile ${dir}
    extract_version_from_json "${SCRIPT_VER}"
    SCRIPT_VER=""
    do-new-tag-version "$RESULT_VER"
    echo -e "\n${I_WARN}${LIGHTBLUE}PATH ./$directory_name: ${LIGHTYELLOW}Changes detected, need bump version: FROM $RESULT_VER TO $RESULT_TAG"
    do-package_JSON_file-bump "$RESULT_VER" "$RESULT_TAG" "$directory_name"
    V_PREV="$RESULT_VER"
    V_NEW="$RESULT_TAG"
    do-commit "./$directory_name project version: updated from $RESULT_VER to $RESULT_TAG"

    #Clean Variables
    RESULT_VER=""
    RESULT_TAG=""
    V_PREV=""
    V_NEW=""
    echo -e "\n=============================================================================="
}
###########################################################################################################################################################################
process-arguments "$@"

#get highest tag number
VERSION=$(git describe --abbrev=0 --tags 2>/dev/null)

# iF NOT VERSION CREATE FIRST ONE
if [ -z $VERSION ]; then
    echo "No tag present."
    echo "Creating tag: $V_NEW_TAG"
    git tag $V_NEW_TAG
    git push --tags
    echo "Tag created and pushed: $V_NEW_TAG"
    exit 0
else
    do-new-tag-version "$VERSION"
    V_NEW_TAG="$RESULT_TAG"
fi

#get current hash and see if it already has a tag
GIT_COMMIT=$(git rev-parse HEAD)
CURRENT_COMMIT_TAG=$(git describe --contains $GIT_COMMIT 2>/dev/null)
CURRENT_COMMIT_TAG=$(git describe --contains $(git rev-parse HEAD) 2>/dev/null)
GET_LIST_FILES_CHANGED_LAST_COMMIT=$(git show --oneline --name-only --pretty='' HEAD)

#Current commit tag only tag if no tag already (would be better if the git describe command above could have a silent option)
if [ -z "$CURRENT_COMMIT_TAG" ]; then

    # ## Check array and return a list of path
    # GetParentOfFilesChangedInGitCommit "$GET_LIST_FILES_CHANGED_LAST_COMMIT"
    # # Set space as the delimiter
    # IFS=' '
    # # Read the split words into an array based on space delimiter
    # read -a strarr <<<"$PARENT_PROJECTS_DIR"
    # # Print each value of the array by using the loop
    # for directory_name in "${strarr[@]}"; do

    # done
    PARENT_PROJECTS_DIR=$(cut -d '/' -f 1 <<<"$GET_LIST_FILES_CHANGED_LAST_COMMIT")
    #GET UNIQ VALUES
    read -ra strarr <<<$(awk -v RS="[ \n]" -v ORS=" " '!($0 in a){print;a[$0]}' <(echo $PARENT_PROJECTS_DIR))
    for directory_name in "${strarr[@]}"; do
        PKG_JSON="$MODULE_DIR/$directory_name"
        #check if is directory
        if [[ -d $PKG_JSON ]]; then
            #In case of the procject math then extract version from json file
            if [[ "$directory_name" == "components" || "$directory_name" == "core" || "$directory_name" == "storybook" ]]; then
                process_versioning ${PKG_JSON}
            fi
        fi
        PKG_JSON=""
        directory_name=""
    done
    process_versioning ""
    do-changelog
    # # Default release note
    # echo "${S_NORM}$(npm run changelog)"

    # do-branch "$V_NEW_TAG"
    # do-commit
    # do-tag "$VERSION" "$V_NEW_TAG"
    # do-push "$V_NEW_TAG"
    #echo -e "\n =================== \n ✅; The new Tag was created and pushed: $V_NEW_TAG"
else
    echo -e "\n =================== \n 🏁; This commit is already tagged as: $CURRENT_COMMIT_TAG"
fi
