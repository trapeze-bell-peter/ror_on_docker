#!/bin/bash

# List of databases currently available in the docker-compose instance.

psql -qAtX -U postgres -h 0.0.0.0 postgres -c 'SELECT datname FROM pg_database;'
