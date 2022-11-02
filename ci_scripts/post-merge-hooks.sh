#!/usr/bin/env bash
#
#  PROJE_DIR            # GIT_HOOKS PATH
#  branch               # De branch (dev,main, master)
#  UPDATE_STATUS        # IF the changes was applyed
#  SEACH_GIT_LOG        # A Git seach script
#
#
# If any command fails, exit immediately with that command's exit status
set -eo pipefail

#get git hooks path
#MODULE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

#find hoot directory IF IN .GIT/HOOKS ()
PROJE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")" | awk '{ gsub(/.git/, ""); print }' | awk '{ gsub(/hooks/, ""); print }' | sed 's/.$//' | sed 's/.$//')"
#check branch
branch=$(git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,')
UPDATE_STATUS=false
SEACH_GIT_LOG=""

echo "[POST-MERGE: Gravity Hooks].....($branch) =================== $PROJE_DIR================ ${bamboo_working_directory}"

get-json-version() {
    APP_VERSION=$(awk '/version/{gsub(/("|",)/,"",$2);print $2}' package.json)
    APP_NAME=$(awk '/name/{gsub(/("|",)/,"",$2);print $2}' package.json)
}
## function do version if banch is dev or master
do-version() {
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

# BUMP NPM VERSION
do-packagefile-bump() {
    V_NEW=$1
    V_PREV=$2

    NOTICE_MSG="<${S_NORM}package.json${S_NOTICE}>"
    if [ "$SUGGESTED_VERSION" = "$APP_VERSION" ]; then
        echo -e "\n${I_WARN}${NOTICE_MSG}${S_WARN} already contains version ${SUGGESTED_VERSION}."
    else
        NPM_MSG=$(npm version "${SUGGESTED_VERSION}" --git-tag-version=false --force 2>&1)
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

        fi
    fi
}

get-commit-msg() {
    local CMD
    CMD=$([ ! "${APP_VERSION}" = "${SUGGESTED_VERSION}" ] && echo "${APP_VERSION} ->" || echo "to")
    echo bumped "$CMD" "$SUGGESTED_VERSION"
}

# Stage & commit all files modified by this script
do-commit() {
    GIT_MSG+="$(get-commit-msg)"
    GIT_MSG_BODY=" $APP_NAME --new version"
    echo -e "\n${S_NOTICE}[Script] Committing all changes..."
    COMMIT_MSG=$(git commit -m "chore: ${GIT_MSG}" -m "${GIT_MSG_BODY}" 2>&1)

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

#######################################################################################
#
# - In case of DEV or DEVELOP Branch, it check the git commit history using HEAD^
#    Where HEAD is the current and HEAD^ is the previous
#
# - In canse of master, we check all the changes applied betwwen two tags version
#
#######################################################################################
if ([ "$branch" = "dev" ] || [ "$branch" = "develop" ]); then
    SEACH_GIT_LOG="git diff --no-merges --name-only HEAD^"
else
    if ([ "$branch" = "main" ] || [ "$branch" = "develop" ]); then
        OLD_TAG="$(git tag --sort=committerdate | grep -E '^[0-9]' | tail -1)"
        LATEST_TAG="$(git tag | grep -E '^[0-9]' | sort -V | tail -1)"
        SEACH_GIT_LOG="git diff --no-merges --name-only $OLD_TAG..$LATEST_TAG^"
    fi
fi

#######################################################################################
#
# - GET LAST COMMIT CHANGES AND SEARCH BY PROJECT PATH (COMPONENTS, CORE, STORYBOOK ETC..)
#######################################################################################
git_bump="$(
    ${SEACH_GIT_LOG} | awk -F/ '{print $1}' | sort -u |
        {
            while read changed_file; do

                DIR=$changed_file                  ### RETURN THE DIR NAME OF THE FILE
                PATH_S="$PROJE_DIR/$changed_file/" ### CREATE A PATH TO FILE
                NOTICE=""
                NOTICE="[Changes detected]:[/$changed_file] .." ### CREATE MESSAGE

                # ONLY CHECK KNOW SUBPROJECTS
                if [[ "$DIR" == "components" || "$DIR" == "core" || "$DIR" == "storybook" || "$DIR" == "eslint-config" || "$DIR" == "prettier-config" || "$DIR" == "stylelint-config" ]]; then
                    echo "$NOTICE $PATH_S"

                    #MAKE SURE THAT THE CHANGES ARE DIRECTORY PATH
                    if [ -d $PATH_S ]; then

                        cd $PATH_S/

                        #IF FILE JSON EXIST IN PATH
                        json_file="$PATH_S/package.json"
                        if [ -f $json_file ]; then
                            get-json-version
                        else
                            continue
                        fi

                        echo -e "$NOTICE $APP_NAME $APP_VERSION"

                        #check version and bump it
                        do-version $APP_VERSION

                        #apply version into package json
                        if ($VERSION_BUMPED); then
                            echo "[Scripts] bumping verion.. $NOTICE -> $SUGGESTED_VERSION"
                            do-packagefile-bump $SUGGESTED_VERSION $APP_VERSION
                            do-commit
                            SUGGESTED_VERSION=""
                            APP_VERSION=""
                            UPDATE_STATUS=$VERSION_BUMPED
                        fi
                        cd $PROJE_DIR/
                    fi
                fi
            done

            #UPDATE ROOT PROJECT
            if [[ "$UPDATE_STATUS" == true ]]; then
                cd $PROJE_DIR
                get-json-version
                echo "[Changes detected][/root] : $APP_NAME $APP_VERSION"
                do-version $APP_VERSION
                check-tag-exists
                do-packagefile-bump $SUGGESTED_VERSION $APP_VERSION
                do-commit
                echo "[Tagging][/root] : $APP_NAME to $SUGGESTED_VERSION"

                git tag -a $SUGGESTED_VERSION HEAD -m "Gravity new version $SUGGESTED_VERSION"
                git push $branch --tags

                #UPDATE DEV BRACH
                if ([ "$branch" = "main" ]); then
                    git checkout -b tmpbranch     # creates a branch called tmpbranch at HEAD
                    git checkout dev              # switch back to dev branch
                    git merge --ff-only tmpbranch # fast-forward merge dev to tmpbranch, fail if not possible
                    git branch -d tmpbranch       # delete tmpbranch, it's not needed anymore
                    git push origin
                    git checkout $branch
                fi
            fi

        }
)"

if ([ "$branch" = "dev" ] || [ "$branch" = "main" ]); then
    echo "$git_bump"
fi
