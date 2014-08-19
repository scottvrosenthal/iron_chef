# Iron Chef gem

*"Treat your servers like cattle, not pets."*

[![Build Status](https://travis-ci.org/scottvrosenthal/iron_chef.png?branch=master)](https://travis-ci.org/scottvrosenthal/iron_chef)

  - A decentralized approach to managing servers
  - Simple [Chef Solo](http://docs.opscode.com/chef_solo.html) wrapper
  - Built as a [capistrano](https://github.com/capistrano/capistrano) plugin
  - Update multiple nodes in parallel
  - Easily bootstrap nodes via omnibus for Chef configuration

## Install

From the terminal install the gem:

```sh
gem install 'iron_chef'
```

## Bootstrap a new DevOps project

```sh
ironchef devops-project-name
```

The `ironchef` command creates the following DevOps project under the folder `devops-project-name` to get you started.

```ascii
.
├── Capfile
├── Gemfile
├── README.md
├── config
│   └── deploy.rb
├── cookbooks
├── data_bags
│   ├── environments
│   │   ├── production.json
│   │   └── staging.json
│   └── global_settings
│       └── default.json
├── environments
│   ├── production.rb
│   ├── staging.rb
├── nodes
│   ├── production-server1.yml
│   └── staging-server1.yml
├── roles
│   ├── install_server.rb
│   └── setup_server.rb
└── site-cookbooks
    └── commons
        ├── attributes
        │   └── default.rb
        └── recipes
            └── default.rb
```

## Demo DevOps project

  - [Shows how to use ironchef to setup an AWS EC2 instance with nginx](https://github.com/scottvrosenthal/ironchef-demo)
 
## Rails Template DevOps project

  - [An ironchef starter template for building an AWS EC2 instance with rvm, rails, nginx, unicorn, mysql client](https://github.com/scottvrosenthal/ironchef-rails-template)

## Show commands

```sh
cd devops-project-name
cap -T
```

### Example output

```sh
cap bootstrap:chef       # Installs chef via omnibus on host.
cap chef:apply           # Applies the current chef config to the server.
cap chef:clear           # Clears the chef destination folder on the server.
cap chef:dump_nodes_json # Dump each node's dynamically generated node.json file to local ./tmp/nodes directory.
cap chef:nodes           # Shows all nodes available for chef config.
cap chef:unlock          # Clears the chef lockfile on the server.
cap chef:update_code     # Pushes the current chef configuration to the server.
cap chef:why_run         # Runs chef with --why-run flag to to understand the decisions it makes.
cap env:nodes            # Shows chef environment nodes available for chef apply config.
cap env:prepare          # Stub out the chef environment config files.
cap invoke               # Invoke a single command on the remote servers.
cap nodes                # Target individual nodes.
cap production           # Set the target chef environment to 'production'.
cap shell                # Begin an interactive Capistrano session.
cap site_cookbook:stub   # Stub a new chef cookbook in the site-cookbooks folder.
cap staging              # Set the target chef environment to 'staging'.
```

## Example commands

Stub a new cookbook folder under site-cookbooks:

```sh
cap site_cookbook:stub
Created new cookbook stub 'site-cookbooks/cookbook_stub001' in the site-cookbooks folder.
```

Use bash shortcuts to bootstrap multiple boxes at once:

```sh
cap staging-{web,db}1 bootstrap:chef
```

Test chef config on multiple nodes:

```sh
cap staging-{web,db}1 chef:why_run
```

Apply chef configs to multiple nodes in a target environment:

```sh
cap staging all_nodes chef:apply
```

Clear a bad chef config from the server:

```sh
cap staging staging-web1 chef:clear
```

# Nodes

Under the nodes folder name each `node.yml` file something that makes it easy to run bash macro commands.

For example:

```sh
staging-web1.yml
staging-web2.yml
```

This allows you to not have to type in the cloud provider's generated machine name in the terminal:

```sh
cap staging-web{1,2} chef:why_run
```

Here's an example of what a `node.yml` should contain:

*(below is the minimum acceptable values the gem expects for a `node.yml` file)*

```yml
json:
  chef_environment: staging

roles:

recipes:

server:
  host: ec2-xxx-xxx-xxx-xxx.us-west-2.compute.amazonaws.com
```

To map nodes to a target environment, just update the corresponding `environments/staging.yml` file.

Another example with roles and recipes:

```yml
json:
  chef_environment: staging
  mysql:
    server_root_password: n1ceRand0mP@sswordItIs

roles:
  - web_server
  - app_server
  - db_server
  - rails

recipes:
  - nginx
  - mysql:server
  - iptables

server:
  host: ec2-xxx-xxx-xxx-xxx.us-west-2.compute.amazonaws.com
```

If you want to see how the node.yaml file's json attribute will be converted to the corresponding node.json file during a `chef:apply` run:

```sh
cap chef:dump_nodes_json
```

`chef:dump_nodes_json` is useful for debugging the generated node.json per node or allows you to import the node.json files into [chef server](http://docs.opscode.com/chef_overview_server.html) in the future.

# Environments

Iron Chef environments are based on the capistrano multistage idea with a twist.

The environments folder allows you to group nodes into chef environments using `['json']['chef_environment']` attribute in a `node.yml` file.

This allows the target environment to only run tasks for nodes where `['json']['chef_environment']` attribute equals staging:

```sh
cap staging staging-web{1,2,3} chef:clear
```

Also when targeting a chef environment only nodes having that `['json']['chef_environment']` attribute will be available as tasks:

```sh
cap staging all_nodes chef:apply
```

List all nodes that can be tasked in the staging environment:

```sh
cap staging env:nodes
```

If no environment is targeted then you have direct access to all node tasks.

Using the default 'nodes' task:

```sh
cap nodes env:nodes
```

Is the same as:

```sh
cap env:nodes
```

Use `chef:clear` when `chef:apply` throws an exception due to an issue with a cookbook or you need to start over:

```sh
cap staging-web1 chef:clear
```

Add a new environment by adding to the `:chef_environments` variable in `config/deploy.rb` like so:

```ruby
set :chef_environments, %w(staging beta production)
```

Then run `cap env:prepare` to stub out the new `beta` environment.

## Data Bags

Here's an example of how to access data bags per environment or global settings in a recipe:

```ruby
# retrieve environment specific data bag item
env = Chef::DataBagItem.load('environments', node['chef_environment'])
Chef::Log.info("Loaded environments information from DataBagItem env[#{env['id']}]")
Chef::Log.info("Loaded environments information from DataBagItem env[#{env['description']}]")

# retrieve global settings specific data bag item
gs_default = Chef::DataBagItem.load('global_settings', 'default')
Chef::Log.info("Loaded global settings information from DataBagItem gs_default[#{gs_default['id']}]")
Chef::Log.info("Loaded global settings information from DataBagItem gs_default[#{gs_default['description']}]")
```
## Capistrano Config Variables

These are the defaults in case they need to be changed for your environments.

They can easily be overridden inside your DevOps project's `config/deploy.rb` & `environments/chef_environment.rb` files.

```ruby
set :chef_source, '.'
set :chef_destination, '/tmp/chef'
set :chef_cookbooks,   %w(cookbooks site-cookbooks)
set :chef_log_level, 'info'
set :chef_command, '/opt/chef/embedded/bin/ruby /opt/chef/bin/chef-solo -c /tmp/chef/solo.rb'
set :chef_parameters, '--color'
set :chef_excludes, %w(.git .svn nodes)
set :chef_stream_output, false
set :chef_parallel_rsync, true
set :chef_parallel_rsync_pool_size, 10
set :chef_write_to_file, nil
set :chef_lock_file, '/tmp/chef.lock'
set :chef_file_cache_dir, '/tmp/chef_cache'
set :chef_nodes_dir, 'nodes'
set :chef_data_bags_dir, 'data_bags'
set :chef_environment_dir, 'environments'
set :chef_site_cookbook_dir, 'site-cookbooks'
```

## Adding to a remote git repo

  - `git add -f cookbooks/.keep`

Using the default iron_chef gem settings both the `cookbooks` & `site-cookbooks` folders are required by the chef client on the server.

Remember the `site-cookbooks` is where you put your custom cookbooks.

The `cookbooks` folder's purpose is for vendor cookbooks (see below).

## Chef Cookbook Manager gems

If you're new to chef cookbooks, I'd recommend you start with `librarian-chef` first.

#### [librarian-chef](https://github.com/applicationsonline/librarian-chef)

  - add the gem to your DevOps project's Gemfile
  - read up on the gem for commands: [librarian-chef](https://github.com/applicationsonline/librarian-chef)
  - `librarian-chef` will manage the `cookbooks` folder by default

***

#### [berkshelf](https://github.com/RiotGames/berkshelf)

  - add the gem to your DevOps project's Gemfile
  - run `berks init` and say no to conflict with Gemfile
  - read up on the gem for commands: [berkshelf.com](http://berkshelf.com/)
  - `berks install` will download the cookbooks, but it doesn't copy them by default to the `cookbooks` folder
  - after you `berks install` you need to copy the vendor cookbooks to the `cookbooks`
    * before a `chef:apply` run `berks install --path cookbooks`

***

## Changelog
  - v0.0.10
    * Initial release
  - v0.0.11
    * Make chef_file_cache_dir available as a variable & default to /tmp/chef_cache
  - v0.0.12
    * Added task to create a cookbook stubbed folder for site-cookbooks, inside project `cap site_cookbooks:stub`    
