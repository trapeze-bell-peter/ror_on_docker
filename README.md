# The case for using docker-compose

There are many good guides on how to setup docker-composer to run `Ruby-on-Rails`. 
[Here](https://www.firehydrant.io/blog/developing-a-ruby-on-rails-app-with-docker-compose/) is one of the better
ones.  The most cited reasons for using `docker` and `docker-compose`: ensuring that everyone has a consistent
development environment.  Reasons cited as to why branches could be inconsistent:

1. different run-time environment
2. different Ruby or Ruby-on-Rails versions
3. using different Gems
4. database structure may be changing as a new feature is being added

My reasons for wanting to use Docker really focuses on the fourth point.  I believe that Ruby, when used with `rvm`,
`gem` and `bundler` between them do a good job of ensuring that everyone is using a consistent underlying library of
Ruby code and Ruby Gems.

The big issue really arises around database structure and managing consistent deployment.  Typically, we might have a
single Postgres instance running on the development machine.  As we start each new project, we need to create a new
database within the Postgres instance.  If we need to have different versions of Postgres running, then this becomes a
bigger issue.  Beyond that, creating new databases within one instance requires careful setup.

An even bigger issue is when you need to switch between two branches of Git that have different database models.  For
me, the following scenario is quite common: I am knee-deep in developing a major new feature that includes some changes
to the database model.  Therefore, my database schema looks different to that in production.  A user now flags an issue
with production that needs urgent attention.  What do I do?  Before introducing Docker, I would dump my database with
new schema to a file, switch branches, fetch the production database, load into Postgres overwriting the old database,
and so on.  I could easily loose one to two hours in the switch and switch back.

`docker-compose` gives us a way of having different database instances running on the same development machine.  This
gives us the best of both world: we can use Rubymine, rvm and bundler to ensure that the Ruby environment is consistent
for developers working on the same branch, while allowing us to run different databases associated with different
branches.  Because we are still running the application locally, our usual tool chain, particularly in Rubymine, works
fine with no tweaking.

This article and associated Git repository shows how I have started using Docker-compose to have different setups within
the same development directory structure.  Switching between different development branches, particularly when the
database schema is evolving is more straightforward.  However, as I explain at to the end of the article its not a
panacea.

# The toy problem

The associated Git repository contains the various files here, together with a toy application that uses the concepts
described here to run.  In common with Ruby-on-Rails convention (almost over configuration), the toy problem is an
ultra-simplistic bulletin board.  Users of the bulletin board can:

* View, edit and delete users and posts (standard CRUD).
* Create new posts.  When a user creates a new post, they receive an email thanking them.
* Request a word count across all posts.  This uses an ActiveJob based on Sidekiq to do the calculation.  After 10
  seconds, the controller will redirect the user to a page that should show the word counts as retrieved from the
  Rails cache.  Another 10 seconds later the Rails cache entry is deleted.

# Setting up Docker and Docker-compose

Digital Ocean have a good description of how to install Docker on Ubuntu
[here](https://www.digitalocean.com/community/tutorials/how-to-install-docker-compose-on-ubuntu-18-04).

Additionally, you may want to setup your Rubymine to support Docker. 
[This](https://www.jetbrains.com/help/ruby/docker.html) provides a good description.  However, ignore the sections on
running Ruby in `docker-compose`.

# Configuring your Ruby-on-Rails environment to use docker-compose for development

Here is my suggested docker-compose.yaml file which should be placed in the top level directory:

```yaml
version: '3.7'

services:
  db:
    image: postgres:latest
    restart: always
    ports:
      - 5432:5432
    environment:
      POSTGRES_USER: 'postgres'
      POSTGRES_PASSWORD: 'postgres'
    volumes:
      - database_data:/var/lib/postgresql/data

volumes:
  database_data:
    driver: local
```

This provides a configuration that will provide a docker-compose database instance for the local directory.

Now we need to modify our `config/database.yml` file:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 10
  username: postgres
  password: postgres

development:
  <<: *default
  url: <%= ENV['POSTGRES_URL'] || 'postgres://0.0.0.0/' %>
  database: <%= "#{`git symbolic-ref --short HEAD`.strip.underscore}_development" %>

test:
  <<: *default
  url: <%= ENV['POSTGRES_URL'] || 'postgres://0.0.0.0/' %>
  database: <%= "#{`git symbolic-ref --short HEAD`.strip.underscore}_test" %>
```

Note the us of the `POSTGRES_URL` environment variable.  We will need this later when we get a Sidekiq instance
talking to the database from within the `docker-compose` system.

If you have a local Postgres instance that is started as a service during boot-up, disable it now.  Otherwise, docker
will fail to bind to the Postgres port as it is already taken. To instantiate everything, simply run:

```bash
# docker-compose up --build
```

Docker should report that it has successfully created the containers and started the postgres instance tied to the
standard Postgres port of 5432.  Note, that the configuration is setup so that it will create a database named
_git_branch_name_\_development.

Once this has been setup, we can use standard rails to create a database:

```bash
rails db:create
```

This will create an empty database for development and test.  This database does not have any tables in as yet.  For
development, the best approach is to dump an operational database and import it into your development environment:

```bash
# psql -U postgres -h 0.0.0.0 app_development < db/expenses.dump
```

If you need to look at what is happening inside the database, you can use the following command to launch a SQL
interactive session:

```bash
# psql -U postgres -h 0.0.0.0 app_development
```

This will prompt you for your password which is `postgres` as defined in the `docker-compose.yaml` file. I find it very
useful to configure PGPASSWORD in my environment to avoid having to constantly re-enter the password.  You can set this
anyway you set environment variables.  Personally, I have set it in my `.bashrc` file:

```bash
export PGPASSWORD=postgres
```


For test, it is best to load the schema into the database, but leave the database largely empty:

```bash
# rails db:schema:load RAILS_ENV=test
# rails db:seed RAILS_ENV=test
```

You should now be able to use your Rails app as normal with the main app running locally, while database actions are
done within the Docker container.

# Adding a Rails Cache

I will talk in the next section about Sidekiq.  However, in order to use Sidekiq you really need a cache in which to
store any results a Sidekiq job may produce that you want to pass back to the web application.  Simply add the following
in the service section of your `docker-compose.yaml` file.

```yaml
  rails-cache:
    image: redis
    command: redis-server /usr/local/etc/redis/redis.conf
    ports:
      - 6380:6380
    volumes:
      - ./rails-cache.conf:/usr/local/etc/redis/redis.conf
```

We also need to change the way we configure the Redis store to act as a Rails cache:

```Ruby
  # Use Redis as our cache store.
  config.cache_store = :redis_cache_store, { url: ENV['RAILS_CACHE_URL'] || 'redis://0.0.0.0:6380' }
```

This ensures that when Sidekiq uses the Rails cache it uses the correct URL

This will create a Redis instance in Docker exposing port 6380 to the outside world.  It uses a redis config file
located in the project's top level directory to configure the Redis instance.  This file is very standard, but with one
key difference:

```
# Separate port for the rails cache server.  6379 is used for sidekiq 
port 6380
```

This moves the Redis port used to 6380 leaving port 6379 available for Sidekiq.  You can get this added by now running:

```bash
# docker-compose up --build
```

# Adding Sidekiq

This is only a little more involved than getting the Rails cache up and running.  We will need two containers for this. 
The first provides the Sidekiq server, while the second provides Sidekiq's Redis store.  As there is no ready-to-use
image for Sidekiq we are also going to have to create a dockerfile that specifies the build process.  Let's start with
that file first.  This file is best called `sidekiq.dockerfile` and sits in the top level directory of the Ruby-on-Rails
directory structure alongside `docker.compose`.

```docker
FROM ruby:2.6.1
MAINTAINER marko@codeship.com

# Install apt based dependencies required to run Rails as
# well as RubyGems. As the Ruby image itself is based on a
# Debian image, we use apt-get to install those.
RUN apt-get update && apt-get install -y build-essential postgresql-client yarn

# Need a newer version of nodejs than from standard Debian
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash - && apt-get install -y nodejs
RUN npm install -g yarn

# Configure the main working directory. This is the base
# directory used in any further RUN, COPY, and ENTRYPOINT
# commands.
RUN mkdir -p /app
WORKDIR /app

# Copy the Gemfile as well as the Gemfile.lock and install
# the RubyGems. This is a separate step so the dependencies
# will be cached unless changes to one of those two files
# are made.
COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle install --jobs 20 --retry 5
```

This basically, creates a container to run the Sidekiq ruby code.  It then copies the local app directory to the
container, together with the `Gemfile` and the `Gemfile.lock` before running bundler in the container to fetch the
appropriate Gems.

With that in place, we can now add the descriptions of the two containers to the `docker.compose` file:

```yaml
  sidekiq:
    build:
      context: .
      dockerfile: sidekiq.dockerfile
    command: bundle exec sidekiq -v
    environment:
      POSTGRES_URL: 'postgres://db/'
      RAILS_CACHE_URL: 'redis://rails-cache:6380/'
    links:
      - db
      - sidekiq-cache
      - rails-cache
    volumes:
      - '.:/app'

  sidekiq-cache:
    image: redis
    command: redis-server /usr/local/etc/redis/redis.conf
    ports:
      - 6379:6379
    volumes:
      - ./sidekiq.conf:/usr/local/etc/redis/redis.conf
```

We also need to tell the Rails app where to look for the Sidekiq Redis instance.  Add the following lines to your
`config/environments/development.rb` file:

```ruby
# Configure to talk to sidekiq in its local docker container.
Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://sidekiq-cache' }
  config.logger.level = Logger::DEBUG
  Rails.logger = Sidekiq::Logging.logger
end

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://0.0.0.0:6379/0' }
  config.logger.level = Logger::DEBUG
  Rails.logger = Sidekiq::Logging.logger
end
```

Rebuild the docker containers with:

```bash
# docker-compose up --build
```

# Mailcatcher

I find it very useful to use the [mailcatcher](https://github.com/sj26/mailcatcher) in development to make
sure that the mail aspects of the application are working.  Again, we can run this in its own container.  Simply add
this to the services section of the yaml file:

```yaml
  mailcatcher:
    image: zolweb/docker-mailcatcher:latest
    ports:
      - "1025:1025"
      - "1080:1080"
```

Configuration in the config/environments/development.rb file:

```ruby
  # Don't care if the mailer can't send.
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = { address: '0.0.0.0', port: 1025 }
  config.action_mailer.raise_delivery_errors = false
```

Rebuild the docker containers with:

```bash
# docker-compose up --build
```

# Git hooks

When branching in development, the developer could of course either run `db:create` to create a new database, or
manually copy from an existing database associated with another branch.  However, I felt it would be advantageous
to provide suitable Git hooks that do this automatically.  Likewise, it would be good to remove development and
test databases for which the corresponding local branch no longer exists.

Git provides an in-built mechanism in the form of a director `.git/hooks`.  In this, the user can store scripts to
be run at suitable points. Unfortunately, its not perfect since the hooks are not directly associated with branching or
deleting a branch.  Instead, they are associated with checkout and merging.

To this end, I have created three bash scripts that reside in the `bin` directory:

* `bin/copy-db-to-new-branch.sh`
* `bin/drop-dbs-not-on-branch.sh`
* `bin/ls-dbs.sh`

There were two reasons to put them in the bin directory rather than straight in Git's `hooks` directory:

* By being in the bin directory, they are under version control in the same way as any other project file.
* They can be invoked directly by the user from the command line if necessary.

So that Git can use them, we do require to setup two symbolic links from `hooks` to the the `bin` directory:

```bash
$ cd .git/hooks
$ ln -s ../../bin/copy-db-to-new-branch.sh post-checkout 
$ ln -s ../../bin/drop-dbs-not-on-branch.sh post-merge

```
  
I should make clear that I am neither a Git nor a Bash scripting expert, so there may be better ways of doing this.  But
it does seem to work.  Here is `copy-db-to-new-branch.sh`:

```bash
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
``` 

This script will copy the database `master_development` to the current branch so long as the current branch is not
master.  I have found that copying from `master` seems to work better, rather than copying from the existing branch even
if I am branching off a development branch.  `master` is always self-consistent, and I can then modify the new
database to reflect a different structure by using Rails migrations.

Here is the corresponding `drop-dbs-not-on-brach.sh`:

```bash
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
```

Both scripts can fail and Git will report if they do.  The main failure mode is if the database we are copying from does
not exist.

# Final thoughts 

Overall, this works well.  I have moved most of my RoR projects on my local machine over to using `docker-compose`.

My biggest gripe is that I can end up with a docker-compose container running in another project and blocking a key
port.  It would be nice if I could define different subdomains for each project so that does not arise anymore.

I would also love to write a Rails generator that does all this setup automatically.  But that is a bigger undertaking and
therefore for another day.
