# Iron Chef gem

[![Build Status](https://www.travis-ci.org/scottvrosenthal/iron_chef.png?branch=master)](https://www.travis-ci.org/scottvrosenthal/iron_chef)

  - A scrappy DevOps gem
  - Simple [Chef Solo](http://docs.opscode.com/chef_solo.html) wrapper
  - Built as a [capistrano](https://github.com/capistrano/capistrano) plugin
  - Update multiple nodes in parallel
  - Easily bootstrap nodes for Chef configuration

## Install

From the terminal install the gem:

```sh
gem install 'iron_chef'
```

## Bootstrap a new DevOps project

```sh
ironchef project-name-devops
```

The `ironchef` command creates the following DevOps project under the folder `project-name-devops` to get you started.

```ascii
.
├── Capfile
├── Gemfile
├── README.md
├── config
│   └── deploy.rb
├── cookbooks
├── data_bags
│   └── global.json
├── environments
│   ├── production.rb
│   ├── production.yml
│   ├── staging.rb
│   └── staging.yml
├── nodes
│   ├── production-server1.yml
│   └── staging-server1.yml
└── roles
```

## Show commands

```sh
cd project-name-devops
cap -T
```

### Example output

```sh
cap bootstrap:amazon # Installs chef via yum on a amazon host.
cap bootstrap:centos # Installs chef via yum on a centos host.
cap bootstrap:redhat # Installs chef via yum on a redhat host.
cap bootstrap:ubuntu # Installs chef via apt on a ubuntu host.
cap chef:apply       # Applies the current chef config to the server.
cap chef:clear       # Clears the chef destination folder on the server.
cap chef:nodes       # Shows all nodes available for chef config.
cap chef:unlock      # Clears the chef lockfile on the server.
cap chef:update_code # Pushes the current chef configuration to the server.
cap chef:why_run     # Runs chef with --why-run flag to to understand the decisions it makes.
cap env:nodes        # Shows chef environment nodes available for chef apply config.
cap env:prepare      # Stub out the chef environment config files.
cap invoke           # Invoke a single command on the remote servers.
cap nodes            # Target individual nodes.
cap production       # Set the target chef environment to 'production'.
cap shell            # Begin an interactive Capistrano session.
cap staging          # Set the target chef environment to 'staging'.
```

## Example commands

Use bash shortcuts to bootstrap multiple boxes at once:

```sh
cap staging-{web,db}1 bootstrap:centos
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
  environment: staging

roles:

recipes:

server:
  host: ec2-xxx-xxx-xxx-xxx.us-west-2.compute.amazonaws.com
```

To map nodes to a target environment, just update the corresponding `environments/staging.yml` file.

Another example with roles and recipes:

```yml
json:
  environment: staging
  mysql:
    server_root_password: n1ceRand0mP@sswordItIs

roles:
  - centos
  - rails

recipes:
  - nginx
  - mysql:server
  - iptables

server:
  host: ec2-xxx-xxx-xxx-xxx.us-west-2.compute.amazonaws.com
```

# Environments

Iron Chef environments are based on the capistrano multistage idea with a twist.

The environments folder allows you to group nodes into environments using the `env_name.yml` file.

Example `staging.yml` file:

```yml
nodes:
  - staging-db1
  - staging-web1
  - staging-web2
  - staging-web3
```

This allows the target environment to only run tasks for nodes listed in `staging.yml` file:

```sh
cap staging staging-web{1,2,3} chef:clear
```

Also by targeting an environment only nodes defined in the `env_name.yml` will be available as tasks:

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

## Changelog
  - v0.0.4
    * Initial release