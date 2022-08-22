#!/bin/bash
IFS=$'\n'

# Settings
PRODUCT_NAME="Gravity"
REPOSITORY_URL="https://<jira-server>/browse"
AZURE_DEVOPS_GIT_URL="https://<tenant>.visualstudio.com/<project>/_git/<repository>"
INCLUDE_FEATURES=1
INCLUDE_FIXES=1
INCLUDE_CHORES=1

# Get a list of all tags in reverse order
GIT_TAGS=$(git tag -l --sort=-version:refname)

DATE_NOW=$(date '+%d-%m-%Y')
# Add title
MARKDOWN="# Changelog ${PRODUCT_NAME}\n<sup>Last updated: $DATE_NOW</sup>\n\n"

# Make the tags an array and include HEAD as the first (so we can include unreleased changes)
TAGS=("HEAD")
TAGS+=($GIT_TAGS)

for TAG_INDEX in "${!TAGS[@]}"; do
    FEATURES=()
    FIXES=()
    CHORES=()

    LATEST_TAG=${TAGS[TAG_INDEX]}
    PREVIOUS_TAG=${TAGS[TAG_INDEX + 1]}
    TAG_DATE=$(git for-each-ref --format="%(taggerdate:format:%d-%m-%Y)" "refs/tags/${LATEST_TAG}")

    # Get a log of commits that occured between two tags
    # We only get the commit hash so we don't have to deal with a bunch of ugly parsing
    # See Pretty format placeholders at https://git-scm.com/docs/pretty-formats
    if [[ -z $PREVIOUS_TAG ]]; then
        COMMITS=$(git log $LATEST_TAG --pretty=format:"%H")
    else
        COMMITS=$(git log $PREVIOUS_TAG..$LATEST_TAG --pretty=format:"%H")
    fi

    # Loop over each commit and look for feature, bugfix or chore commits
    for COMMIT in $COMMITS; do
        # Get the subject of the current commit
        SUBJECT=$(git log -1 ${COMMIT} --pretty=format:"%s")

        # Is it marked as a feature commit?
        FEATURE=$(grep -Eo "feat:" <<<"$SUBJECT")
        # Is it marked as a bugfix commit?
        FIX=$(grep -Eo "fix:" <<<"$SUBJECT")
        # Is it marked as a chore commit?
        CHORE=$(grep -Eo "chore:" <<<"$SUBJECT")

        # Get the body of the commit
        BODY=$(git log -1 ${COMMIT} --pretty=format:"%b")
        # Does the body contain a link to a JIRA-number
        JIRA_ID=$(grep -Eo "JIRA-[[:digit:]]+" <<<$BODY)
        # Get last JIRA-number of the body (body might reference others)
        JIRA_ID=$(echo "$JIRA_ID" | tail -1)

        # Only include in list if commit contains a reference to a JIRA-number
        if [[ $JIRA_ID ]]; then
            if [[ $FEATURE ]] && [[ $INCLUDE_FEATURES = 1 ]]; then
                search_str="feat:"
                subject="${SUBJECT#*$search_str}"
                FEATURES+=("- [$JIRA_ID]($REPOSITORY_URL/$JIRA_ID):${subject}")
            elif [[ $FIX ]] && [[ $INCLUDE_FIXES = 1 ]]; then
                search_str="fix:"
                subject=${SUBJECT#*$search_str}
                FIXES+=("- [$JIRA_ID]($REPOSITORY_URL/$JIRA_ID):${subject}")
            elif [[ $CHORE ]] && [[ $INCLUDE_CHORES = 1 ]]; then
                search_str="chore:"
                subject=${SUBJECT#*$search_str}
                CHORES+=("- [$JIRA_ID]($REPOSITORY_URL/$JIRA_ID):${subject}")
            fi
        fi
    done

    # Continue to next release if no commits are available since the previous release
    if [[ -z $COMMITS ]]; then
        continue
    fi

    if [[ $LATEST_TAG = "HEAD" ]]; then
        MARKDOWN+="## Unreleased\n\n"
    else
        MARKDOWN+="## Release $LATEST_TAG ($TAG_DATE)\n\n"
    fi

    # List features
    if [[ $FEATURES ]]; then
        FEATURES=($(for l in ${FEATURES[@]}; do echo $l; done | sort -u))
        MARKDOWN+="### ✨ Features\n\n"
        for FEAT in "${FEATURES[@]}"; do
            MARKDOWN+="$FEAT\n"
        done
        MARKDOWN+="\n"
    fi

    # List bugfixes
    if [[ $FIXES ]]; then
        FIXES=($(for l in ${FIXES[@]}; do echo $l; done | sort -u))
        MARKDOWN+="### 🐛 Bugfixes\n\n"
        for FIX in "${FIXES[@]}"; do
            MARKDOWN+="$FIX\n"
        done
        MARKDOWN+="\n"
    fi

    # List chores
    if [[ $CHORES ]]; then
        CHORES=($(for l in ${CHORES[@]}; do echo $l; done | sort -u))
        MARKDOWN+="### 🧹 Chores\n\n"
        for CHORE in "${CHORES[@]}"; do
            MARKDOWN+="$CHORE\n"
        done
        MARKDOWN+="\n"
    fi

    # Append full changelog
    if [[ $LATEST_TAG = "HEAD" ]]; then
        MARKDOWN+="📖 [Full changelog](${AZURE_DEVOPS_GIT_URL}/branchCompare?baseVersion=GT${PREVIOUS_TAG}&targetVersion=GBdevelop)\n\n"
    elif [[ -z $PREVIOUS_TAG ]]; then
        # First release, no way to compare
        echo ""
    else
        MARKDOWN+="📖 [Full changelog](${AZURE_DEVOPS_GIT_URL}/branchCompare?baseVersion=GT${PREVIOUS_TAG}&targetVersion=GT${LATEST_TAG})\n\n"
    fi

done

# Save our markdown to a file
printf "%b" "$MARKDOWN" >CHANGELOG.md
