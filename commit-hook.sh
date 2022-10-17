#!/usr/bin/env bash

###############################################################################
#
# Automatically detects a merge on to master from a gitflow-style release
# branch, e.g. release-1.1.1-alpha.  If the merged branch matches, the major,
# minor and patch versions are determined and a new release tag is created
# locally. If remote origin exists, this tag will automatically be pushed.
#
# In addition to creating a tag, the release branch will automatically be
# merged into the develop branch. If the branch has already been merged this
# won't cause any changes. Again if remote origin exists these updates to
# develop will be automatically pushed up.
#
###############################################################################

tag_repo() {
    git tag "$1.$2.$3"
    git checkout develop
    git merge $merged_branch_name
    git checkout master
}

push_changes() {
    # Check if remote origin exists
    git ls-remote --exit-code origin

    if [[ $? = 0 ]]; then
        git push origin --tags
        git push origin develop
        echo -e "\033[0;32mNew release tagged and pushed to remote origin."
        # SAFETY SAFETY let's not delete develop by accident here...
        if [[ $"merged_branch_name" -ne "develop" ]]; then
            echo "Discarding branch $merged_branch_name..."
            git branch -d $merged_branch_name
        fi
    else
        echo -e "\033[0;31mRemote origin does not exist, releaes tag and develop branch not pushed!"
    fi
}

target_branch=$(git rev-parse --symbolic --abbrev-ref HEAD)
reflog_message=$(git reflog -1)
merged_branch_name=$(echo $reflog_message | cut -d" " -f 4 | sed "s/://")
release_pattern="^release-([0-9]+)\.([0-9]+)\.(.*)$"
hotfix_pattern="^hotfix-([0-9]+)\.([0-9]+)\.(.*)$"

if [ "$target_branch" = "master" ]; then
    if [[ "$merged_branch_name" =~ $release_pattern ]] || [[ "$merged_branch_name" =~ $hotfix_pattern ]]; then

        echo -e "\033[1;33mNew release merge detected, auto-creating release tag and merging changes into develop..."

        major_ver=${BASH_REMATCH[1]}
        minor_ver=${BASH_REMATCH[2]}
        patch_ver=${BASH_REMATCH[3]}

        tag_repo $major_ver $minor_ver $patch_ver
        push_changes $merged_branch_name
    fi
fi
