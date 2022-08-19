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

is_number() {
    case "$1" in
    '' | *[!0-9]*) return 0 ;;
    *) return 1 ;;
    esac
}

# find ./ -maxdepth 2 -type f -name "package.json" ! -path "./.git/*" ! -path "./node_modules/*" ! -path ".*/node_modules/*" #-ls
# find ./ -maxdepth 2 -type f ! -path "./.git/*;./node_modules/*" | while read -r _file; do
#     echo "Process ${_file} here"
# done

#get highest tag number
VERSION=$(git describe --abbrev=0 --tags 2>/dev/null)

if [ -z $VERSION ]; then
    NEW_TAG="1.0.0"
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

    for value in $GET_LIST_FILES_CHANGED_LAST_COMMIT; do
        echo $value
    done

    echo "Bumping to a new Version: CURRENT $VERSION to $NEW_TAG"
    # Default release note
    # git tag -a $NEW_TAG -m "Bump new Tag version ${NEW_TAG}."
    #git push --tags
    echo "Tag created and pushed: $NEW_TAG"
else
    echo "This commit is already tagged as: $CURRENT_COMMIT_TAG"
fi
