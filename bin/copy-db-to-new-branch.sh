#!/bin/bash

NEW_BRANCH_NAME=$(git symbolic-ref --short HEAD)

# Don't bother copying the master_branch onto itself.
if [[ $NEW_BRANCH_NAME=='master_developmet' ]]; then
    exit 0
fi

TARGET_DATABASE=${NEW_BRANCH_NAME}_development
TARGET_DATABASE_EXISTS=`psql -qAtX -U postgres -h 0.0.0.0 postgres -c "SELECT COUNT(*) FROM pg_database WHERE datname='${TARGET_DATABASE}';"`

if [[ $TARGET_DATABASE_EXISTS=='0' && ]]; then
    createdb -h 0.0.0.0 -U postgres -T master_development ${TARGET_DATABASE}
fi
