#!/bin/bash

# shellcheck disable=SC2288
true

GET_LIST_FILES_CHANGED_LAST_COMMIT=$(git show --oneline --name-only --pretty='' HEAD)

is_number() {
    case "$1" in
    '' | *[!0-9]*) return 0 ;;
    *) return 1 ;;
    esac
}

# Show credits & help
usage() {
    local SCRIPT_VER SCRIPT_HOME
    # NPM environment variables are fetched with cross-platform tool cross-env (overkill to use a dependency, but seems the only way AFAIK to get npm vars)
    SCRIPT_VER=$(cd "$MODULE_DIR" && grep version package.json | head -1)
    SCRIPT_AUTH=$(cd "$MODULE_DIR" && grep author package.json | head -1)
    SCRIPT_HOME=$(cd "$MODULE_DIR" && grep homepage package.json | head -1 | sed -ne 's/.*\(http[^"]*\).*/\1/p')
    SCRIPT_NAME=$(cd "$MODULE_DIR" && grep name package.json | head -1)

    local env_vars=(SCRIPT_VER SCRIPT_AUTH SCRIPT_NAME)

    for env_var in "${env_vars[@]}"; do
        env_var_val=$(eval "echo \$${env_var}" | awk -F: '{ print $2 }' | sed 's/[",]//g' | sed "s/^[ \t]*//")

        eval "${env_var}=\"${env_var_val}\""
    done
}

# Process script options
process-arguments() {
    local OPTIONS OPTIND OPTARG

    # Get positional parameters
    while getopts ":v:p:m:u:f:ahbncl" OPTIONS; do # Note: Adding the first : before the flags takes control of flags and prevents default error msgs.
        case "$OPTIONS" in
        h)
            # Show help
            usage
            exit 0
            ;;
        v)
            # User has supplied a version number
            V_USR_SUPPLIED=$OPTARG
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
        f)
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}JSON file via [-f]: <${S_NORM}${OPTARG}${S_LIGHT}>"
            # Store JSON filenames(s)
            JSON_FILES+=("$OPTARG")
            ;;
        p)
            FLAG_PUSH=true
            PUSH_DEST=${OPTARG} # Replace default with user input
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}Pushing to <${S_NORM}${PUSH_DEST}${S_LIGHT}>, as the last action in this script."
            ;;
        a)
            AUTO_VERSION=true
            PUSH_AUTO_VERSION=${OPTARG}
            echo -e "\n${S_LIGHT}Option set: ${S_NOTICE}, ${S_NORM}false${S_LIGHT} as AUTOMATED VERSION."
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

# If there are no commits in repo, quit, because you can't tag with zero commits.
check-commits-exist() {
    if ! git rev-parse HEAD &>/dev/null; then
        echo -e "\n${I_STOP} ${S_ERROR}Your current branch doesn't have any commits yet. Can't tag without at least one commit." >&2
        echo
        exit 1
    fi
}

# Suggests version from VERSION file, or grabs from user supplied -v <version>.
# If none is set, suggest default from options.

# - If <package.json> doesn't exist, warn + exit
# - If -v specified, set version from that
# - Else,
#   - Grab from package.json
#   - Suggest incremented number
#   - Give prompt to user to modify
# - Set globally

# According to SemVer 2.0.0, given a version number MAJOR.MINOR.PATCH, suggest incremented value:
# — MAJOR version when you make incompatible API changes,
# — MINOR version when you add functionality in a backwards compatible manner, and
# — PATCH version when you make backwards compatible bug fixes.
process-version() {
    # As a minimum pre-requisite ver-bump needs a version number from a JSON file
    # to read + bump. If it doesn't exist, throw an error + exit:
    if [ -f "$VER_FILE" ] && [ -s "$VER_FILE" ]; then
        # Get the existing version number
        V_PREV=$(sed -n 's/.*"version":.*"\(.*\)"\(,\)\{0,1\}/\1/p' "$VER_FILE")

        if [ -n "$V_PREV" ]; then
            echo -e "\n${S_NOTICE}Current version read from <${S_QUESTION}${VER_FILE}${S_NOTICE}> file: ${S_QUESTION}$V_PREV"
            set-v-suggest "$V_PREV" # check + increment patch number
        else
            echo -e "\n${I_WARN} ${S_ERROR}Error: <${S_QUESTION}${VER_FILE}${S_WARN}> doesn't contain a 'version' field!\n"
            exit 1
        fi
    else
        echo -ne "\n${S_ERROR}Error: <${S_QUESTION}${VER_FILE}${S_WARN}> "
        if [ ! -f "$VER_FILE" ]; then
            echo "was not found!"
        elif [ ! -s "$VER_FILE" ]; then
            echo "is empty!"
        fi
        exit 1
    fi

    # If a version number is supplied by the user with [-v <version number>] — use it!
    if [ -n "$V_USR_SUPPLIED" ]; then
        echo -e "\n${S_NOTICE}You selected version using [-v]:" "${S_WARN}${V_USR_SUPPLIED}"
        V_NEW="${V_USR_SUPPLIED}"
    else

        if [[ "$AUTO_VERSION" != true && "$PUSH_AUTO_VERSION" != false ]]; then
            echo -e "\n${S_QUESTION}Automatic version selected [${S_NORM}$V_SUGGEST${S_QUESTION}]: "
            echo -e "$S_WARN"

            # User accepted the suggested version
            V_NEW=$V_SUGGEST
        else
            # Display a suggested version
            echo -ne "\n${S_QUESTION}Enter a new version number or press <enter> to use [${S_NORM}$V_SUGGEST${S_QUESTION}]: "
            echo -ne "$S_WARN"
            read -r V_USR_INPUT

            if [ "$V_USR_INPUT" = "" ]; then
                # User accepted the suggested version
                V_NEW=$V_SUGGEST
            else
                V_NEW=$V_USR_INPUT
            fi
        fi
    fi
}

set-v-suggest() {
    local IS_NO V_PREV_LIST V_MAJOR V_MINOR V_PATCH

    IS_NO=0
    # shellcheck disable=SC2207
    V_PREV_LIST=($(echo "$1" | tr '.' ' '))
    V_MAJOR=${V_PREV_LIST[0]}
    V_MINOR=${V_PREV_LIST[1]}
    V_PATCH=${V_PREV_LIST[2]}

    is_number "$V_MAJOR"
    ((IS_NO = "$?"))
    is_number "$V_MINOR"
    ((IS_NO = "$?" && "$IS_NO "))

    # If major & minor are numbers, then proceed to increment patch
    if [ "$IS_NO" = 1 ]; then

        if [ "$FLAG_BUMP_MINOR" = true ]; then
            V_MINOR=$((V_MINOR + 1))
            V_PATCH=$((0))
            V_SUGGEST="$V_MAJOR.$V_MINOR.$V_PATCH"
            return
        else
            is_number "$V_PATCH"
            if [ "$?" == 1 ]; then
                V_PATCH=$((V_PATCH + 1)) # Increment
                V_SUGGEST="$V_MAJOR.$V_MINOR.$V_PATCH"
                return
            fi
        fi

    fi

    echo -e "\n${I_WARN} ${S_WARN}Warning: ${S_QUESTION}${1}${S_WARN} doesn't look like a SemVer compatible version number! Couldn't automatically bump the patch value. \n"
    # If patch not a number, do nothing, keep the input
    V_SUGGEST="$1"
}

#
check-branch-notexist() {
    [ "$FLAG_NOBRANCH" = true ] && return
    if git rev-parse --verify "${REL_PREFIX}${V_NEW}" &>/dev/null; then
        echo -e "\n${I_STOP} ${S_ERROR}Error: Branch <${S_NORM}${REL_PREFIX}${V_NEW}${S_ERROR}> already exists!\n"
        exit 1
    fi
}

# Only tag if tag doesn't already exist
check-tag-exists() {
    TAG_MSG=$(git tag -l "v${V_NEW}")
    if [ -n "$TAG_MSG" ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error: A release with that tag version number already exists!\n\n$TAG_MSG\n"
        exit 1
    fi
}
extract_version_from_pkgjson() {
    # NPM environment variables are fetched with cross-platform tool cross-env (overkill to use a dependency, but seems the only way AFAIK to get npm vars)
    SCRIPT_VER="$1"
    RETURNV=
    for env_var in "${SCRIPT_VER[@]}"; do
        env_var_val=$(eval "echo \$${env_var}" | awk -F: '{ print $2 }' | sed 's/[",]//g' | sed "s/^[ \t]*//")
        RETURNV="$env_var_val"
    done
    PCKJ_VERSION="$RETURNV"
}

do_message() {
    local proj=$1
    local message_1=$2
    local message_2=$3

    MESSAGE=""
    if [ "$FLAG_BUMP_MINOR" = true ]; then
        MESSAGE="ATTENTION release MINOR version"
    else
        MESSAGE="PATCH version"
    fi
    echo -e " --Reading package.json ...\n --${S_NORM}${I_WARN}${proj}: Has changes to be bumped: Actual ${message_1} $MESSAGE TO ${message_2}"
}

do-update-parent-project() {
    echo -e "${S_NOTICE}Cheking commits into parents projects."
    PARENT_PROJECTS_DIR=$(cut -d '/' -f 1 <<<"$GET_LIST_FILES_CHANGED_LAST_COMMIT")
    #GET UNIQ VALUES
    read -ra strarr <<<$(awk -v RS="[ \n]" -v ORS=" " '!($0 in a){print;a[$0]}' <(echo $PARENT_PROJECTS_DIR))
    for project_dir in "${strarr[@]}"; do
        PKG_JSON="${MODULE_DIR}/${project_dir}"
        # check if is directory
        if [[ -d $PKG_JSON ]]; then

            #In case of the procject math then extract version from json file
            if [[ "$project_dir" == "components" || "$project_dir" == "core" || "$project_dir" == "storybook" ]]; then
                #search and read Package.json within dir
                SCRIPT_VER=$(cd "$PKG_JSON" && grep version package.json | head -1)
                echo -e "${S_NOTICE} --Changes detected in Parent Project == $project_dir ==\n --./$project_dir package.json$SCRIPT_VER"
                extract_version_from_pkgjson "${SCRIPT_VER}"
                set-v-suggest "$PCKJ_VERSION"
                do_message ${project_dir} ${PCKJ_VERSION} ${V_SUGGEST}
                do-package_JSON_file-bump "$PCKJ_VERSION" "$V_SUGGEST" "$project_dir"
                V_SUGGEST=""
                PCKJ_VERSION=""
            fi
        fi

    done

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
        if [[ ! -z "$V_PKG_JSON_DIR" && -d $V_PKG_JSON_DIR ]]; then

            ## NAVIGATE INTO DIR
            cd "./$V_PKG_JSON_DIR/"
            do-packagefile-bump "$V_NEW_TAG_LOCAL" "$V_PKG_JSON_DIR"
            # NAVIGATE OUT DIRECTORY
            cd ..
        elif [[ -z "$V_PKG_JSON_DIR" && -d $V_PKG_JSON_DIR ]]; then
            do-packagefile-bump "$V_NEW_TAG_LOCAL" "$V_PKG_JSON_DIR"
        fi

    fi
}

do-packagefile-bump() {
    local V_PROJECT_DIR="./"

    if [ ! -z "$1" ]; then
        V_NEW="$1"
    fi
    if [ ! -z "$2" ]; then
        V_PROJECT_DIR="$2"
    fi

    NPM_MSG=$(npm version "${V_NEW}" --git-tag-version=false --force 2>&1)
    # shellcheck disable=SC2181
    if [ ! "$?" -eq 0 ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error updating <package.json> and/or <package-lock.json>.\n\n$NPM_MSG\n"
        exit 1
    else
        git add package.json
        GIT_MSG+="chore: updated package.json, "
        if [ -f package-lock.json ]; then
            git add package-lock.json
            GIT_MSG+="updated package-lock.json, "
            NOTICE_MSG+=" and <${S_NORM}package-lock.json${S_NOTICE}>"
        fi
        echo -e "\n${I_OK} $V_PROJECT_DIR ${S_NOTICE}Bumped version in ${NOTICE_MSG}.\n"
    fi

}

# Change `version:` value in JSON files, like packager.json, composer.json, etc
bump-json-files() {
    # if [ "$FLAG_JSON" != true ]; then return; fi

    JSON_PROCESSED=() # holds filenames after they've been changed

    for FILE in "${JSON_FILES[@]}"; do
        if [ -f "$FILE" ]; then
            # Get the existing version number
            V_PREV=$(sed -n 's/.*"version":.*"\(.*\)"\(,\)\{0,1\}/\1/p' "$FILE")

            if [ -z "$V_PREV" ]; then
                echo -e "\n${I_STOP} ${S_ERROR}Error updating version in file <${S_NORM}$FILE${S_NOTICE}> - a version name/value pair was not found to replace!"
            elif [ "$V_PREV" = "$V_NEW" ]; then
                echo -e "\n${I_ERROR} ${S_WARN}File <${S_QUESTION}$FILE${S_WARN}> already contains version ${S_NORM}$V_PREV"
            else
                # Write to output file
                FILE_MSG=$(jq --arg V_NEW "$V_NEW" '.version = $V_NEW' "$FILE" >"${FILE}.temp")

                if [ -z "$FILE_MSG" ]; then
                    echo -e "\n${I_OK} ${S_NOTICE}Updated file <${S_NORM}$FILE${S_NOTICE}> from ${S_QUESTION}$V_PREV ${S_NOTICE}-> ${S_QUESTION}$V_NEW"
                    # rm -f "${FILE}.temp"
                    mv -f "${FILE}.temp" "${FILE}"
                    # Add file change to commit message:
                    GIT_MSG+="updated $FILE, "
                fi
            fi

            JSON_PROCESSED+=("$FILE")
        else
            echo -e "\n${S_WARN}File <${S_NORM}$FILE${S_WARN}> not found."
        fi
    done
    # Stage files that were changed:
    ((${#JSON_PROCESSED[@]})) && git add "${JSON_PROCESSED[@]}"
}

# Handle VERSION file - for backward compatibility
do-versionfile() {
    if [ -f VERSION ]; then
        GIT_MSG+="updated VERSION, "
        echo "$V_NEW" >VERSION # Overwrite file
        # Stage file for commit
        git add VERSION

        echo -e "\n${I_OK} ${S_NOTICE}Updated [${S_NORM}VERSION${S_NOTICE}] file." \
        "\n${I_WARN} ${S_ERROR}Deprecation warning: using a <${S_NORM}VERSION${S_ERROR}> file is deprecated since v0.2.0 - support will be removed in future versions."
    fi
}

get-commit-msg() {
    local CMD
    CMD=$([ ! "${V_PREV}" = "${V_NEW}" ] && echo "${V_PREV} ->" || echo "to")
    echo bumped "$CMD" "$V_NEW"
}

capitalise() {
    echo "$(tr '[:lower:]' '[:upper:]' <<<"${1:0:1}")${1:1}"
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
do-branch() {
    [ "$FLAG_NOBRANCH" = true ] && return

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
    [ "$FLAG_NOCOMMIT" = true ] && return

    GIT_MSG+="$(get-commit-msg)"
    echo -e "\n${S_NOTICE}Committing..."
    COMMIT_MSG=$(git commit -m "${COMMIT_MSG_PREFIX}${GIT_MSG}" 2>&1)
    # shellcheck disable=SC2181
    if [ ! "$?" -eq 0 ]; then
        echo -e "\n${I_STOP} ${S_ERROR}Error\n$COMMIT_MSG\n"
        exit 1
    else
        echo -e "\n${I_OK} ${S_NOTICE}$COMMIT_MSG"
    fi
}

# Create a Git tag using the SemVar
do-tag() {
    if [ -z "${REL_NOTE}" ]; then
        # Default release note
        git tag -a "v${V_NEW}" -m "Tag version ${V_NEW}."
    else
        # Custom release note
        git tag -a "v${V_NEW}" -m "${REL_NOTE}"
    fi
    echo -e "\n${I_OK} ${S_NOTICE}Added GIT tag"
}

# Pushes files + tags to remote repo. Changes are staged by earlier functions
do-push() {
    [ "$FLAG_NOCOMMIT" = true ] && return

    if [ "$FLAG_PUSH" = true ]; then
        CONFIRM="Y"
    else
        echo -ne "\n${S_QUESTION}Push tags to <${S_NORM}${PUSH_DEST}${S_QUESTION}>? [${S_NORM}N/y${S_QUESTION}]: "
        read -r CONFIRM
    fi

    case "$CONFIRM" in
    [yY][eE][sS] | [yY])
        echo -e "\n${S_NOTICE}Pushing files + tags to <${S_NORM}${PUSH_DEST}${S_NOTICE}>..."
        PUSH_MSG=$(git push "${PUSH_DEST}" v"$V_NEW" 2>&1) # Push new tag
        if [ ! "$PUSH_MSG" -eq 0 ]; then
            echo -e "\n${I_STOP} ${S_WARN}Warning\n$PUSH_MSG"
            # exit 1
        else
            echo -e "\n${I_OK} ${S_NOTICE}$PUSH_MSG"
        fi

        ;;
    esac
}
