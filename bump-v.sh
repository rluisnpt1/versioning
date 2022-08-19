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
NEW_TAG="0.1.0" # This is suggested in case VERSION file or user supplied version via -v is missing
PACKAGEJS_VER_FILE="package.json"
GIT_MSG=""
REL_NOTE=""
REL_PREFIX="release-"
COMMIT_MSG_PREFIX="chore: " # Commit msg prefix for the file changes this script makes
PUSH_DEST="origin"
JSON_FILES=()

PARENT_PROJECTS_DIR=("")
SHOULD_UPDATE_COMPONENTS=false
SHOULD_UPDATE_CORE=false
SHOULD_UPDATE_STORYBOOK=false
SHOULD_UPDATE_ROOT=true

is_number() {
    case "$1" in
    '' | *[!0-9]*) return 0 ;;
    *) return 1 ;;
    esac
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

## An Array of string separed by space
CheckParentToUpdateVersion() {
    # Set space as the delimiter
    IFS=' '
    # #Read the split words into an array based on space delimiter
    read -a strarr <<<"$1"
    # Print each value of the array by using the loop
    for val in "${strarr[@]}"; do
        #printf "$val\n"
        case $val in

        webproj1)
            PKG_JSON="$MODULE_DIR/$val/$PACKAGEJS_VER_FILE"
            SCRIPT_VER=$(cd "$MODULE_DIR/$val/" && grep version package.json | head -1)
            echo "${SCRIPT_VER}"
            SHOULD_UPDATE_COMPONENTS=true
            ;;

        webproj2)
            PKG_JSON="$MODULE_DIR/$val/$PACKAGEJS_VER_FILE"
            echo "CHANGES DETECTED AT: $val Update File: $PKG_JSON"
            SHOULD_UPDATE_CORE=true
            ;;

        webproj3)
            echo "CHANGES DETECTED AT: $val"
            SHOULD_UPDATE_STORYBOOK=true
            ;;
        *)
            echo "CHANGES DETECTED: UPDATE ROOT PROJ"
            ;;
        esac
    done
}

do-package_JSON_file-bump() {
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
            GIT_MSG+="updated package.json, "
            if [ -f package-lock.json ]; then
                git add package-lock.json
                GIT_MSG+="updated package-lock.json, "
                NOTICE_MSG+=" and <${S_NORM}package-lock.json${S_NOTICE}>"
            fi
            echo -e "\n${I_OK} ${S_NOTICE}Bumped version in ${NOTICE_MSG}."
        fi
    fi
}

# find ./ -maxdepth 2 -type f -name "package.json" ! -path "./.git/*" ! -path "./node_modules/*" ! -path ".*/node_modules/*" #-ls
# find ./ -maxdepth 2 -type f ! -path "./.git/*;./node_modules/*" | while read -r _file; do
#     echo "Process ${_file} here"
# done

#get highest tag number
VERSION=$(git describe --abbrev=0 --tags 2>/dev/null)

# iF NOT VERSION CREATE FIRST ONE
if [ -z $VERSION ]; then
    echo "No tag present."
    echo "Creating tag: $NEW_TAG"
    git tag $NEW_TAG
    git push --tags
    echo "Tag created and pushed: $NEW_TAG"
    exit 0
fi

#replace . with space so can split into an array
VERSION_BITS=(${VERSION//./ })
#get number parts and increase last one by 1
VNUM1=${VERSION_BITS[0]}
VNUM2=${VERSION_BITS[1]}
VNUM3=${VERSION_BITS[2]}
VNUM3=$((VNUM3 + 1))

#create new tag
NEW_TAG="${VNUM1}.${VNUM2}.${VNUM3}"

#get current hash and see if it already has a tag
GIT_COMMIT=$(git rev-parse HEAD)
CURRENT_COMMIT_TAG=$(git describe --contains $GIT_COMMIT 2>/dev/null)
GET_LIST_FILES_CHANGED_LAST_COMMIT=$(git show --oneline --name-only --pretty='' HEAD)

#Current commit tag only tag if no tag already (would be better if the git describe command above could have a silent option)
if [ -z "$CURRENT_COMMIT_TAG" ]; then
    GetParentOfFilesChangedInGitCommit "$GET_LIST_FILES_CHANGED_LAST_COMMIT"
    CheckParentToUpdateVersion "$PARENT_PROJECTS_DIR"

    # if [ "$SHOULD_UPDATE_COMPONENTS" = true ]; then
    #     echo 'Bumping '
    # fi
    # if [ "$SHOULD_UPDATE_CORE" = true ]; then
    #     echo '2'
    # fi
    # if [ "$SHOULD_UPDATE_STORYBOOK" = true ]; then
    #     echo '3'
    # fi
    echo "Bumping to a new Version: CURRENT $VERSION to $NEW_TAG"
    # Default release note
    # git tag -a $NEW_TAG -m "Bump new Tag version ${NEW_TAG}."
    #git push --tags
    echo "Tag created and pushed: $NEW_TAG"
else
    echo "This commit is already tagged as: $CURRENT_COMMIT_TAG"
fi
