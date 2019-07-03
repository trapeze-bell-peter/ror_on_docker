#!/bin/bash

# Post merge hook to iterate over all databases user databases ending in _development or _test and check if they
# still have a branch associated with them.  If they don't then remove.

mapfile -t DATABASE_ARRAY < <( psql -qAtX -U postgres -h 0.0.0.0 postgres -c 'SELECT datname FROM pg_database;' )
mapfile -t GIT_BRANCHES < <( git branch --format='%(refname:short)' )

# Check if we can match the database passed as a param with a branch.  If not, drop the DB.
function drop_if_no_branch {
    local db=$1

    for GIT_BRANCH in "${GIT_BRANCHES[@]}"
    do
        if [[ $1 == "${GIT_BRANCH}_development" || $1 == "${GIT_BRANCH}_test" ]]; then
            return 0
        fi
    done

    dropdb -U postgres -h 0.0.0.0 $db
}

# Iterate through the array of databases.  Remove any DB for which there is no corresponding branch.  Don't include
# any DBs that end in _development or _test.
for DATABASE in ${DATABASE_ARRAY[@]}; do
    case $DATABASE in
        postgres | template0 | template1 | master_development | master_test ) ;;
        *_development) drop_if_no_branch $DATABASE ;;
        *_test) drop_if_no_branch $DATABASE ;;
    esac
done