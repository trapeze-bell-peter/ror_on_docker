# The case for using docker-compose

There are many good guides on how to setup docker-composer to run `Ruby-on-Rails`. 
[Here](https://www.firehydrant.io/blog/developing-a-ruby-on-rails-app-with-docker-compose/) is one of the better
ones.  The most cited reasons for using `docker` and `docker-compose`: ensuring that everyone has a consistent
development environment.

However, IMHO, most of these miss the point.  The key challenge is making it easy for developers to switch between
different branches of the application rather than ensuring consistency - Ruby with its tools already does a good job on
consistency.  Reasons why branches could be inconsistent:

1. different run-time environment
2. different Ruby or Ruby-on-Rails versions
3. using different Gems
4. database structure may be changing as a new feature is being added

In my view, the first three items are not an issue.  Ruby does a good job of abstracting away from the operating system.
Additionally,  `rvm`, `gem` and `bundler` between them do a good job of ensuring that everyone is using a consistent
underlying library of Ruby code.

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
branches.

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
  url: postgres://0.0.0.0/
  database: <%= "#{`git symbolic-ref --short HEAD`.strip.underscore}_development" %>

test:
  <<: *default
  url: postgres://0.0.0.0/
  database: <%= "#{`git symbolic-ref --short HEAD`.strip.underscore}_test" %>
```

If you have a local Postgres instance that is started as a service during boot-up, disable it now.  Otherwise, docker will fail to bind to the Postgres port as it is already taken. To instantiate everything, simply run:

```bash
# docker-compose up --build
```

Docker should report that it has successfully created the containers and started the postgres instance tied to the
standard Postgres port of 5432.  Note, that the configuration  is setup so that it will create a database named
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

For test, it is best to load the schema into the database, but leave the database largely empty:

```bash
# rails db:schema:load ENV=test
# rails db:seed ENV=test
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
    links:
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

# Mailcatcher



Rebuild the docker containers with:

```bash
# docker-compose up --build
```


```bash
# psql -U postgres -h 0.0.0.0 app_development
```

