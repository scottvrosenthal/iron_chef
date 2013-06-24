# Iron Chef gem

  - A scrappy DevOps gem
  - Simple [Chef Solo](http://docs.opscode.com/chef_solo.html) wrapper
  - Built as a [capistrano](https://github.com/capistrano/capistrano) plugin

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

### example output

```sh
cap bootstrap:centos # Installs chef via yum on a centos host.
cap bootstrap:redhat # Installs chef via yum on a redhat host.
cap bootstrap:ubuntu # Installs chef via apt on an ubuntu host.
cap chef:apply       # Applies the current chef config to the server.
cap chef:clear       # Clears the chef destination folder on the server.
cap chef:nodes       # Shows nodes available for chef config.
cap chef:unlock      # Clears the chef lockfile on the server.
cap chef:update_code # Pushes the current chef configuration to the server.
cap chef:why_run     # Runs chef with --why-run flag to to understand the decisions it makes.
cap env:nodes        # Shows chef environment nodes available for chef apply config.
cap env:prepare      # Stub out the chef environment config files.
cap invoke           # Invoke a single command on the remote servers.
cap production       # Set the target chef environment to 'production'.
cap shell            # Begin an interactive Capistrano session.
cap staging          # Set the target chef environment to 'staging'.

```

## Changelog
  - v0.0.1
    * Initial release