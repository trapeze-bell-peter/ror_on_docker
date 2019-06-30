#!/bin/bash

BRANCHING=$3

if [[ $BRANCHING == '1' ]]; then
    OLD_BRANCH_NAME=$(git reflog | awk 'NR==1{ print $6; exit }')
    NEW_BRANCH_NAME=$(git reflog | awk 'NR==1{ print $8; exit }')

    TARGET_DATABASE=${NEW_BRANCH_NAME}_development
    TARGET_DATABASE_EXISTS=`psql -qAtX -U postgres -h 0.0.0.0 postgres -c "SELECT COUNT(*) FROM pg_database WHERE datname='${TARGET_DATABASE}';"`

    if [[ $TARGET_DATABASE_EXISTS=='0' ]]; then
        createdb -h 0.0.0.0 -U postgres -T ${OLD_BRANCH_NAME}_development ${TARGET_DATABASE}
    fi
fi
