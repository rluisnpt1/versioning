#!/bin/sh

set -o pipefail -e

MODULE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
COMMIT_MSG_PREFIX="chore: "
REL_NOTE=""
branch=$(git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,')
VERSION_BUMPED=false
PUSH_DEST=origin
REL_NOTE="Release version to "
#LOG= "$(git log --date=short --no-merges --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cd) ' --abbrev-commit 0.0.4...0.0.84)"

function get-json-version() {
    APP_VERSION=$(awk '/version/{gsub(/("|",)/,"",$2);print $2}' package.json)
    APP_NAME=$(awk '/name/{gsub(/("|",)/,"",$2);print $2}' package.json)
}
# BUMP NPM VERSION
function do-packagefile-bump() {
    V_NEW=$1
    V_PREV=$2

    NOTICE_MSG="<${S_NORM}package.json${S_NOTICE}>"
    if [ "$V_NEW" = "$V_PREV" ]; then
        echo -e "\n${I_WARN}${NOTICE_MSG}${S_WARN} already contains version ${V_NEW}."
    else
        NPM_MSG=$(npm version "${V_NEW}" --git-tag-version=false --force 2>&1)
        # shellcheck disable=SC2181
        if [ ! "$?" -eq 0 ]; then
            echo -e "\n${I_STOP} ${S_ERROR}Error updating <package.json> and/or <package-lock.json>.\n\n$NPM_MSG\n"
            exit 1
        else
            git add package.json
            GIT_MSG+="bumped version to, "
            if [ -f package-lock.json ]; then
                git add package-lock.json
                GIT_MSG+="updated package-lock.json, "
                NOTICE_MSG+=" and <${S_NORM}package-lock.json${S_NOTICE}>"
            fi
            echo -e "\n${I_OK} ${S_NOTICE}Bumped version in ${NOTICE_MSG}.\n"
        fi
    fi
}

function get-commit-msg() {
    local CMD
    CMD=$([ ! "${V_PREV}" = "${V_NEW}" ] && echo "${V_PREV} ->" || echo "to")
    echo bumped "$CMD" "$V_NEW"
}

# Stage & commit all files modified by this script
function do-commit() {
    GIT_MSG+="$(get-commit-msg)"
    GIT_MSG_BODY=" $APP_NAME --new version"
    echo -e "\n${S_NOTICE}Committing..."
    COMMIT_MSG=$(git commit -m "${COMMIT_MSG_PREFIX}${GIT_MSG}" -m "${GIT_MSG_BODY}" 2>&1)

    #shellcheck disable=SC2181
    # If an error
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

function check-tag-exists() {
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
# Create Tag VERVSION
function do-tag() {
    local OLD="$1"
    local V_NEW="$2"
    #IF NOT MESSAGE IN RELEASE NOTES
    if [ -z "${REL_NOTE}" ]; then
        git tag -a ${V_NEW} -m "Tag to a new version "$OLD" -> ${V_NEW}."
    else
        # Custom release note
        git tag -a ${V_NEW} -m "${REL_NOTE}"
    fi
    echo -e "\n${I_OK} ${S_NOTICE}Added GIT tag"
}

function do-push() {

    echo -e "\n${S_NOTICE}Pushing files + tags to <${S_NORM}${PUSH_DEST}${S_NOTICE}>..."
    PUSH_MSG=$(git push "${PUSH_DEST}" "$V_NEW" 2>&1) # Push new tag
    if [ ! "$PUSH_MSG" -eq 0 ]; then
        echo -e "\n${I_STOP} ${S_WARN}Warning\n$PUSH_MSG"
        # exit 1
    else
        echo -e "\n${I_OK} ${S_NOTICE}$PUSH_MSG"
    fi
}
function do-version() {
    local version=$1
    BASE_LIST=($(echo $version | tr '.' ' '))

    V_MAJOR=${BASE_LIST[0]}
    V_MINOR=${BASE_LIST[1]}
    V_PATCH=${BASE_LIST[2]}

    NOTICE="[Branch: $branch] "

    if ([ "$branch" = "dev" ] || [ "$branch" = "develop" ]); then
        V_PATCH=$((V_PATCH + 1))
        VERSION_BUMPED=true
        NOTICE+="PATCH"
    fi

    if ([ "$branch" = "main" ] || [ "$branch" = "master" ]); then
        V_MINOR=$((V_MINOR + 1))
        V_PATCH=0
        VERSION_BUMPED=true
        NOTICE+="MINOR"
    fi
    SUGGESTED_VERSION="$V_MAJOR.$V_MINOR.$V_PATCH"
}

UPDATE_STATUS=false
# HEAD is the current commit, HEAD^ is the last commit
git diff --no-merges --name-only HEAD^ | awk -F/ '{print $1}' | sort -u |
    {
        while read changed_file; do
            # echo "$MODULE_DIR"
            DIR=$changed_file

            PATH_S="$MODULE_DIR"
            # Replace ci_script dir with subdir
            PATH_S=${PATH_S/ci_scripts/$changed_file}

            if [[ "$DIR" == "components" || "$DIR" == "core" || "$DIR" == "storybook" || "$DIR" == "eslint-config" || "$DIR" == "prettier-config" || "$DIR" == "stylelint-config" ]]; then

                if [ -d $PATH_S ]; then
                    NOTICE=""
                    NOTICE="[Changes detected]:[/$changed_file] .."
                    cd $PATH_S/
                    get-json-version
                    echo "$NOTICE $APP_NAME $APP_VERSION"
                    do-version $APP_VERSION

                    if ($VERSION_BUMPED); then
                        echo "[Scripts] bumping verion.. $NOTICE -> $SUGGESTED_VERSION"
                        do-packagefile-bump $SUGGESTED_VERSION $APP_VERSION
                        V_NEW=$SUGGESTED_VERSION
                        V_PREV=$APP_VERSION

                        do-commit
                        V_NEW=""
                        V_PREV=""
                        UPDATE_STATUS=$VERSION_BUMPED
                    else
                        echo "[changes branch]: $branch is not (dev or main) version not bumped in $APP_NAME."
                    fi
                    cd ../ci_scripts
                fi

            fi
        done #| sort -nr | head -n 1

        #UPDATE ROOT PROJECT
        if [[ "$UPDATE_STATUS" == true ]]; then
            cd ..
            get-json-version
            echo "[Changes detected][/root] : $APP_NAME $APP_VERSION"
            do-version $APP_VERSION
            V_PREV=$APP_VERSION
            V_NEW=$SUGGESTED_VERSION
            check-tag-exists
            do-packagefile-bump $SUGGESTED_VERSION $APP_VERSION
            do-commit
            #TAG Tru pipeline
            # do-tag "$V_PREV" "$V_NEW"
            # do-push
            V_NEW=""
            V_PREV=""
        fi
    }
