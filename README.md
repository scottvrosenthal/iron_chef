# Iron Chef gem

  - A scrappy DevOps gem
  - Simple [Chef Solo](http://docs.opscode.com/chef_solo.html) wrapper
  - Built as a [capistrano](https://github.com/capistrano/capistrano) plugin
  - Update multiple nodes in parallel
  - Easily bootstrap nodes for Chef configuration

## Install

From the terminal install the gem

```sh
gem install 'iron_chef'
```

## Bootstrap a new DevOps project

```sh
ironchef project-name-devops
```

## Show commands

```sh
cd project-name-devops
cap -T
```

### Example output

```sh
cap bootstrap:centos # Installs chef via yum on a centos host.
cap bootstrap:redhat # Installs chef via yum on a redhat host.
cap bootstrap:ubuntu # Installs chef via apt on an ubuntu host.
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

Using bash shortcuts to bootstrap multiple boxes at once:

```sh
cap staging-{web,db}1 bootstrap:centos
```

Test chef config on multiple nodes:

```sh
cap staging-{web,db}1 chef:why_run
```

Apply chef configs to multiple nodes in an environment:

```sh
cap staging all_nodes chef:apply
```

# Nodes

Under the nodes folder name each node.yml file something that makes it easy to run bash macro commands.

For example:

```sh
staging-web1.yml
staging-web2.yml
```

This allows you to not have to type in the cloud provider's generated machine name in the terminal.

```sh
cap staging-web{1,2} chef:why_run
```

Here's an example of what a node.yml should contain:

*(below is the minimum acceptable values the gem expects for a node yml)*

```yml
json:
  environment: staging

roles:

recipes:

server:
  host: ec2-xxx-xxx-xxx-xxx.us-west-2.compute.amazonaws.com
```

To map nodes to a target environment, just update the corresponding environments/staging.yml file.

# Environments

Iron Chef environments are based on the capistrano multistage idea with a twist.

The environments folder allows you to group nodes into environments using the env_name.yml file.

This allows the target environment to only run tasks for nodes listed in staging.yml:

```sh
cap staging staging-web{1,2,3} chef:clear
```

List nodes that can be tasked in the staging environment:

```sh
cap staging env:nodes
```

If an environment isn't specified then you have direct access to all node tasks through the default 'nodes' task.

```sh
cap nodes env:nodes
```

Same as:

```sh
cap env:nodes
```

## Changelog
  - v0.0.2
    * Initial release