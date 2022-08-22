#!/bin/bash

# gravity_v=$(node -pe "require('./package.json')['version']")
# components_v=$(node -pe "require('./webproj1/package.json')['version']")
# core_v=$(node -pe "require('./webproj2/package.json')['version']")

# export VERSION=$(git tag --sort=-committerdate | head -1)
# export PREVIOUS_VERSION=$(git tag --sort=-committerdate | head -2 | awk '{split($0, tags, "\n")} END {print tags[1]}')
# export CHANGES=$(git log --pretty="- %s" $VERSION...$PREVIOUS_VERSION)
# printf "# 🎁 Release notes (\`$VERSION\`)\n\n## Changes\n$CHANGES\n\n## Metadata\n\`\`\`\nThis version -------- $VERSION\nPrevious version ---- $PREVIOUS_VERSION\nTotal commits ------- $(echo "$CHANGES" | wc -l)\n\`\`\`\n" >release_notes.md

# echo "
# gravity: version $gravity_v
# Core: version $components_v
# Components: version $core_v
# "

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
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Update Minor Version when bumping <${S_NORM}${FLAG_BUMP_MINOR}${S_LIGHT}>, as the last action in this script."
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

# Only tag if tag doesn't already exist
check-tag-exists() {
    TAG_MSG=$(git tag -l "v${V_NEW_TAG}")
    if [ -n "$TAG_MSG" ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error: A release with that tag version number already exists!\n\n$TAG_MSG\n"
        exit 1
    fi
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

extract_version_from_json() {
    # NPM environment variables are fetched with cross-platform tool cross-env (overkill to use a dependency, but seems the only way AFAIK to get npm vars)
    SCRIPT_VER="$1"
    RETURNV=
    for env_var in "${SCRIPT_VER[@]}"; do
        env_var_val=$(eval "echo \$${env_var}" | awk -F: '{ print $2 }' | sed 's/[",]//g' | sed "s/^[ \t]*//")
        printf "\n Reading package.json version at $val : $env_var_val"
        RETURNV="$env_var_val"
    done
    result="$RETURNV"
}
updatePackageJsonVersion() {
    V_NEW_TAG_LOCAL="$1"
    NPM_MSG=$(npm version "${V_NEW_TAG_LOCAL}" --git-tag-version=false --force 2>&1)
    # shellcheck disable=SC2181
    if [ ! "$?" -eq 0 ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error updating <package.json> and/or <package-lock.json>.\n\n$NPM_MSG\n"
        exit 1
    else
        git add package.json
        GIT_MSG+="updated package.json, "
        if [ -f package-lock.json ]; then
            git add package-lock.json
            GIT_MSG+="updated package-lock.json, "
            NOTICE_MSG+=" and <${S_NORM}package-lock.json${S_NOTICE}>"
        fi
        echo -e "\n${I_OK} ${S_NOTICE}Bumped version in ${NOTICE_MSG}."
    fi
}

do-package_JSON_file-bump() {
    V_PREV_TAG_LOCAL="$1"
    V_NEW_TAG_LOCAL="$2"
    V_PKG_JSON_DIR="$3"

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

# Dump git log history to CHANGELOG.md
do-changelog() {
    [ "$FLAG_NOCHANGELOG" = true ] && return

    V_PREV="$1"

    local COMMITS_MSG LOG_MSG RANGE

    RANGE=$(["$(git tag -l v"${V_PREV}")"] && echo "v${V_PREV}...HEAD")
    COMMITS_MSG=$(git log --pretty=format:"- %s" "${RANGE}" 2>&1)
    # shellcheck disable=SC2181
    if [ ! "$?" -eq 0 ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error getting commit history since last version bump for logging to CHANGELOG.\n\n$LOG_MSG\n"
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

do-new-tag-version() {
    LOCAL_VERSION="$1"
    #replace . with space so can split into an array
    VERSION_BITS=(${LOCAL_VERSION//./ })
    #get number parts and increase last one by 1
    V_MAJOR=${VERSION_BITS[0]}
    V_MINOR=${VERSION_BITS[1]}
    PATCH=${VERSION_BITS[2]}

    if [ "$FLAG_BUMP_MINOR" = true ]; then
        V_MINOR=$((V_MINOR + 1))
    else
        PATCH=$((PATCH + 1))
    fi

    #create new tag
    RESULT_TAG="${V_MAJOR}.${V_MINOR}.${PATCH}"
}
# find ./ -maxdepth 2 -type f -name "package.json" ! -path "./.git/*" ! -path "./node_modules/*" ! -path ".*/node_modules/*" #-ls
# find ./ -maxdepth 2 -type f ! -path "./.git/*;./node_modules/*" | while read -r _file; do
#     echo "Process ${_file} here"
# done

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
GET_LIST_FILES_CHANGED_LAST_COMMIT=$(git show --oneline --name-only --pretty='' HEAD)

#Current commit tag only tag if no tag already (would be better if the git describe command above could have a silent option)
if [ -z "$CURRENT_COMMIT_TAG" ]; then

    ## Check array and return a list of path
    GetParentOfFilesChangedInGitCommit "$GET_LIST_FILES_CHANGED_LAST_COMMIT"

    # Set space as the delimiter
    IFS=' '

    # Read the split words into an array based on space delimiter
    read -a strarr <<<"$PARENT_PROJECTS_DIR"
    # Print each value of the array by using the loop
    # for val in "${strarr[@]}"; do
    #     message() {
    #         printf "\n $1 changes detected bump version: FROM $2 TO $3 \n"
    #     }
    #     PKG_JSON="$MODULE_DIR/$val"
    #     #check if is directory
    #     if [[ -d $PKG_JSON ]]; then
    #         echo -e "\n =================== $val ==================="
    #         #search and read Package.json within dir
    #         SCRIPT_VER=$(cd "$PKG_JSON" && grep version package.json | head -1)
    #         #In case of the procject math then extract version from json file
    #         if [[ "$val" == "components" || "$val" == "core" || "$val" == "storybook" ]]; then
    #             extract_version_from_json "${SCRIPT_VER}"
    #             do-new-tag-version "$result"
    #             message "$val" "$result" "$RESULT_TAG"
    #             do-package_JSON_file-bump "$result" "$RESULT_TAG" "$val"
    #         fi
    #     fi

    # done

    echo -e "\n =================== \n Bumping GRAVITY PROJECT to a new Version: FROM $VERSION to $V_NEW_TAG"
    do-package_JSON_file-bump "$VERSION" "$V_NEW_TAG"
    # Default release note
    # git tag -a $V_NEW_TAG -m "Bump new Tag version ${V_NEW_TAG}."
    #git push --tags
    echo -e "\n =================== \n ✅; The new Tag was created and pushed: $V_NEW_TAG"
else
    echo -e "\n =================== \n 🏁; This commit is already tagged as: $CURRENT_COMMIT_TAG"
fi
