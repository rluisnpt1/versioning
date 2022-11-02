#!/bin/sh

set -o pipefail -e

#shellcheck disable=SC1090,SC2034,SC1017

MODULE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
NOW="$(date +'%B %d, %Y')"
REPO_URL=$(git config --get remote.origin.url)
REPO_URL=$(node -p "'$REPO_URL'.replace(/^git@/,'https://').replace('.com:','.com/').replace(/\.git$/,'')")
GET_LIST_FILES_CHANGED_LAST_COMMIT=$(git show --oneline --name-only --pretty='' HEAD)
FLAG_BUMP_MINOR=false
COMMIT_MSG_PREFIX="chore: "
GIT_MSG=""
REL_NOTE=""
PRE_RELEASE_SULFIX="v"

# HEAD is the current commit, HEAD^ is the last commit
#GIT_RESET="$(git reset --hard HEAD^)"

GIT_LATEST_STABLE_TAG=$(git -c versionsort.prereleaseSuffix="-rc" tag -l "${PRE_RELEASE_SULFIX}*.*.*" --sort=-v:refname | awk '!/rc/' | head -n 1)

GIT_LAST_TAG_VERSION=$(git describe --abbrev=0 --tags 2>/dev/null)

# Process script options
function process-arguments() {
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
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Update Minor Version when bumping to <${S_NORM}${FLAG_BUMP_MINOR}${S_LIGHT}>. \n"
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

function capitalise() {
    echo "$(tr '[:lower:]' '[:upper:]' <<<"${1:0:1}")${1:1}"
}

function message() {
    msg_detail=""
    if [ "$FLAG_BUMP_MINOR" = true ]; then
        msg_detail="RELEASE MINOR"
    else
        msg_detail="PATCH version"
    fi
    echo -e "-- $1: Changes was detected.\n-- VERSION: $2\n-- New version required $msg_detail: FROM $2 --> $3 \n"
}

function get_version_pkg_json() {
    # SCRIPT_VER=$(cd "$PKG_JSON" && grep version package.json | head -1)
    #GET_VERSION_PKG_JSON="require('./package.json').version"}
    local GET_VERSION_PKG_JSON="require('./package.json').version"
    GET_NAME_PKG_JSON=$(grep name package.json | cut -d':' -f 2 | cut -d'"' -f 2)
    VERSION=$(node -pe "$GET_VERSION_PKG_JSON")
}

function check_version_pkg_json() {
    local dirpath="$1"
    #check if param is empty if so, it check the package.json in the root project
    if [ -z "$dirpath" ]; then
        echo -e "\n\$root directory"
        get_version_pkg_json
    else
        #in case there exist sub projects with package.json, navigate into the directore
        cd ./$dirpath
        get_version_pkg_json
        cd ..
    fi
    VERSION=$VERSION
    PROJECTNAME=$GET_NAME_PKG_JSON
    #PATHPROJECT=$MODULE_DIR/$directory_name
    # get current version number
    echo -e "==================================================\
    \nPATH: $PATHPROJECT\n-- ./$dirpath package.json: $VERSION\n"
}

# Only tag if tag doesn't already exist
check-tag-exists() {
    if [ "$TAG_PREFIX" = true ]; then
        TAG_MSG=$(git tag -l "v${V_NEW}")
    else
        TAG_MSG=$(git tag -l "${V_NEW}")
    fi
    if [ -n "$TAG_MSG" ]; then
        git restore . --staged
        git restore .
        sleep .4
        echo -e "\n${I_STOP} ${S_ERROR}Error: A release with that '$TAG_MSG' tag version number already exists! Rolling back all changes... \n-- to $V_PREV\n"
        #undo changes Obs: git clean -f -d will remove newly created files and directories (BEWARE!)

        exit 1
    fi
}
## get a list of first parent of files changes
function get_git_dir_files_changes() {
    local path_filescommited="$1"
    local proj_dir_name=("")

    for value in $path_filescommited; do
        ## get name of first subdirectory
        projectDirRepo="$(cut -d '/' -f 1 <<<"$value")"
        # Add new element at the end of the array
        proj_dir_name="$proj_dir_name $projectDirRepo"
    done
    PARENT_PROJECTS_DIR="$proj_dir_name"
    PARENT_PROJECTS_DIR=$(printf '%s\n' "$PARENT_PROJECTS_DIR" | awk -v RS='[,[:space:]]+' '!a[$0]++{printf "%s%s", $0, RT}')
    PARENT_PROJECTS_DIR="${PARENT_PROJECTS_DIR%,*}"
}

function do-new-tag-version() {
    local LOCAL_VERSION="$1"
    #replace . with space so can split into an array
    local VERSION_BITS=(${LOCAL_VERSION//./ })
    #get number parts and increase last one by 1
    V_MAJOR=${VERSION_BITS[0]}
    V_MINOR=${VERSION_BITS[1]}
    PATCH=${VERSION_BITS[2]}

    if [ "$FLAG_BUMP_MINOR" = true ]; then
        V_MINOR=$((V_MINOR + 1))
        PATCH=$((0))
    else
        PATCH=$((PATCH + 1))
    fi
    #create new tag
    RESULT_TAG="${V_MAJOR}.${V_MINOR}.${PATCH}"
}

function update_Package_Json() {
    local V_NEW_TAG_LOCAL="$1"
    NPM_MSG=$(npm version "${V_NEW_TAG_LOCAL}" --git-tag-version=false 2>&1)
    # shellcheck disable=SC2181
    if [ ! "$?" -eq 0 ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error updating <package.json> and/or <package-lock.json>.\n\n$NPM_MSG\n"
        exit 1
    else
        git add package.json
        GIT_MSG+="updated package.json, "
        if [ -f package-lock.json ]; then
            git add package-lock.json
            GIT_MSG+="and package-lock.json, "
            NOTICE_MSG+=" and <${S_NORM}package-lock.json${S_NOTICE}>"
        fi
        echo -e "\n${I_OK} ${S_NOTICE}Bumped version in ${NOTICE_MSG}."
    fi
}

function do-package_JSON_file-bump() {
    local V_PREV_TAG="$1"
    V_NEW_TAG="$2"

    local V_DIR_NAME="$3"
    local V_DIR_PATH="$MODULE_DIR/$V_DIR_NAME"

    echo -e "\n${I_WARN}${NOTICE_MSG}${S_WARN} Changing version...."

    NOTICE_MSG="<${S_NORM}package.json${S_NOTICE}>"
    if [ "$V_NEW_TAG" = "$V_PREV_TAG" ]; then
        echo -e "\n${I_WARN}${NOTICE_MSG}${S_WARN} already contains version ${V_NEW_TAG}."
    else
        # IF CONTAINS SUB PROJECT, CHECK IF PARENT IS DIRECTORY
        if [[ -z !$V_DIR_NAME && -d $V_DIR_PATH ]]; then
            echo -e "./$V_DIR_NAME/"
            ## NAVIGATE INTO DIR
            cd "./$V_DIR_NAME/"
            update_Package_Json "$V_NEW_TAG"
            # NAVIGATE OUT OF SUB DIRECTORY
            cd ..
        elif [[ -z $V_DIR_NAME ]]; then
            update_Package_Json "$V_NEW_TAG"
        fi
    fi
}

#Do not checkout a new branch
function do-branch() {
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
}

function get-commit-msg() {
    local CMD
    CMD=$([ ! "${V_PREV}" = "${V_NEW}" ] && echo "${V_PREV} ->" || echo "to")
    echo bumped "$CMD" "$V_NEW"
}

# Stage & commit all files modified by this script
function do-commit() {
    [ "$FLAG_NOCOMMIT" = true ] && return

    GIT_MSG+="$(get-commit-msg)"
    GIT_MSG_BODY="${PROJECTNAME} $(get-commit-msg)"
    echo -e "\n${S_NOTICE}Committing..."
    COMMIT_MSG=$(git commit -m "${COMMIT_MSG_PREFIX}${GIT_MSG}" -m "${GIT_MSG_BODY}" 2>&1)

    #shellcheck disable=SC2181
    if [ ! "$?" -eq 0 ]; then
        git restore . --staged
        git restore .
        sleep .4
        echo -e "\n${I_STOP} ${S_ERROR}Error\n$COMMIT_MSG\n"
        exit 1
    else
        echo -e "\n${I_OK} ${S_NOTICE}$COMMIT_MSG"
    fi
}

function do-tag() {
    local OLD="$1"
    local V_NEW="$2"

    #IF NOT MESSAGE IN RELEASE NOTES
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
function do-push() {
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
        PUSH_MSG=""
        # PUSH_MSG=$(git push "${PUSH_DEST}" "$V_NEW" 2>&1) # Push new tag
        if [ ! "$PUSH_MSG" -eq 0 ]; then
            echo -e "\n${I_STOP} ${S_WARN}Warning\n$PUSH_MSG"
            exit 1
        else
            echo -e "\n${I_OK} ${S_NOTICE}$PUSH_MSG"
        fi
        ;;
    esac
}

function BumpVParentProjects() {
    #Check commit changes
    get_git_dir_files_changes $GET_LIST_FILES_CHANGED_LAST_COMMIT

    # Set space as the delimiter
    IFS=' '
    # Read the split words into an array based on space delimiter
    read -a project_changes_array <<<"$PARENT_PROJECTS_DIR"
    # each value of the array by using the loop
    for directory_name in "${project_changes_array[@]}"; do
        PKG_JSON="$MODULE_DIR/$directory_name"
        #check if is directory
        if [[ -d $PKG_JSON ]]; then
            check_version_pkg_json $directory_name
            do-new-tag-version $VERSION
            message "${PROJECTNAME}" "${VERSION}" "$RESULT_TAG"
            do-package_JSON_file-bump "$VERSION" "$RESULT_TAG" "$directory_name"
        fi
        do-commit
    done
}

function BumpMainProject() {
    #UPDATE MAIN PROJECT
    check_version_pkg_json
    do-new-tag-version $VERSION
    message "${PROJECTNAME}" "${VERSION}" "$RESULT_TAG"
    V_PREV=${VERSION}
    V_NEW=${RESULT_TAG}
    check-tag-exists
    do-package_JSON_file-bump "$V_PREV" "$V_NEW"

    #do-branch "$V_NEW"
    do-commit
    do-tag "${V_PREV}" "${V_NEW}"
    #do-push "${V_NEW}"
}

process-arguments "$@"
# Execute script
BumpVParentProjects
BumpMainProject
