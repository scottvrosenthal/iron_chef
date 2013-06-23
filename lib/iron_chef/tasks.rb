require 'json'
require 'fileutils'

Capistrano::Configuration.instance.load do

  set :chef_version, '=11.4.0'
  set :chef_source, '.'
  set :chef_destination, "/tmp/chef"
  set :chef_cookbooks,   %w(cookbooks)
  set :chef_log_level, 'info'
  set :chef_command, 'chef-solo -c solo.rb'
  set :chef_parameters, '--color'
  set :chef_excludes, %w(.git .svn nodes)
  set :chef_stream_output, false
  set :chef_parallel_rsync, true
  set :chef_parallel_rsync_pool_size, 10
  set :chef_syntax_check, false
  set :chef_write_to_file, nil
  set :chef_runner, nil
  set :chef_lock_file, '/tmp/chef.lock'
  set :chef_nodes_dir, 'nodes'
  set :chef_environment_dir, 'environments'

  namespace :chef do

    desc "Pushes the current chef configuration to the server."
    task :update_code, :except => { :nochef => true } do
      iron_chef.rsync
    end

    desc "Runs chef with --why-run flag to to understand the decisions it makes."
    task :why_run, :except => { :nochef => true } do
      iron_chef.lock
      transaction do
        on_rollback { iron_chef.unlock }
        iron_chef.prepare
        update_code
        iron_chef.why_run
        iron_chef.unlock
      end
    end

    desc "Applies the current chef config to the server."
    task :apply, :except => { :nochef => true } do
      iron_chef.lock
      transaction do
        on_rollback { iron_chef.unlock }
        iron_chef.prepare
        update_code
        iron_chef.apply
        iron_chef.unlock
      end
    end

    desc "Clears the chef lockfile on the server."
    task :unlock, :except => { :nochef => true } do
      iron_chef.unlock
    end
    
    desc "Clears the chef destination folder on the server."
    task :clear, :except => { :nochef => true } do
      run iron_chef.prepare_sudo_cmd("rm -rf #{chef_destination}/*")
      iron_chef.unlock
    end

    desc "Shows nodes available for chef config."
    task :nodes, :except => { :nochef => true } do
      puts iron_chef.nodes_list
    end

  end ## end chef namespace ##

  ## begin env tasks

  unless exists?(:chef_environments)
    location = fetch(:chef_environment_dir, 'environments')
    set :chef_environments, Dir["#{location}/*.rb"].map { |f| File.basename(f, ".rb") }
  end

  chef_environments.each do |name|
    desc "Set the target chef environment to '#{name}'."
    task(name) do
      location = fetch(:chef_environment_dir, 'environments')
      set :chef_environment, name.to_sym
      if File.exist?(File.join(location, "#{chef_environment}.rb"))
        load "#{location}/#{chef_environment}"

        set(:chef_env_nodes) { YAML.load(File.read("#{location}/#{chef_environment}.yml"))["nodes"] }

        env_nodes = fetch(:chef_env_nodes, nil)

        iron_chef.tasks_for_env(env_nodes)

      end
    end
  end

  on :load do
    if chef_environments.include?(ARGV.first)
      # Execute the specified chef environment so that recipes required in environment can contribute to task list
      find_and_execute_task(ARGV.first) if ARGV.any?{ |option| option =~ /-T|--tasks|-e|--explain/ }
    else
      # Execute the default chef environment so that recipes required in environment can contribute tasks
      find_and_execute_task(default_chef_environment) if exists?(:default_chef_environment)
    end
  end

  namespace :env do
    desc "[internal] Ensure that a chef environment has been selected."
    task :ensure do
      if !exists?(:chef_environment)
        if exists?(:default_chef_environment)
          logger.important "Defaulting to '#{default_chef_environment}'"
          find_and_execute_task(default_chef_environment)
        else
          abort "No chef environment specified. Please specify one of: #{chef_environments.join(', ')} (e.g. 'cap #{chef_environments.first} #{ARGV.last}')"
        end
      end
    end

    desc "Stub out the chef environment config files."
    task :prepare do
      location = fetch(:chef_environment_dir, 'environments')
      FileUtils.mkdir_p(location)
      chef_environments.each do |name|
        rb_env_file = File.join(location, name + ".rb")
        unless File.exists?(rb_env_file)
          File.open(rb_env_file, "w") do |f|
            f.puts "# #{name.upcase}-specific chef environment configuration"
            f.puts "# please put general chef environment config in config/deploy.rb"
          end
          puts "Created chef environment config files for: #{name}"
        end
        yml_env_file = File.join(location, name + ".yml")
        unless File.exists?(yml_env_file)
          File.open(yml_env_file, "w") do |f|
            f.puts "# #{name.upcase}-specific chef environment node list\nnodes:\n  - #{name}-server1"
          end
        end
        nodes_location  = fetch(:chef_nodes_dir, 'nodes')
        yml_env_node_file = File.join(nodes_location, "#{name}-server1.yml")
        unless File.exists?(yml_env_node_file)
          File.open(yml_env_node_file, "w") do |f|
            f.puts "json:\n  environment: #{name}\n\nroles:\n\nrecipes:\n\nserver:\n  public_dns: ec2-xxx-xxx-xxx-xxx.us-west-2.compute.amazonaws.com"
          end
        end
      end
    end

    desc "Shows chef environment nodes available for chef apply config."
    task :nodes, :except => { :nochef => true } do
      puts iron_chef.env_nodes_list
    end

  end

  on :start, "env:ensure", :except => chef_environments + ['env:prepare']

  ## end env tasks

  ## begin bootstrap namespace ##

  namespace :bootstrap do

    desc "Installs chef via apt on an ubuntu host."
    task :ubuntu do
      run "mkdir -p #{chef_destination}"
      script = <<-BASH
#!/bin/sh

if type -p chef-solo > /dev/null; then
  echo "Using chef-solo at `which chef-solo`"
else
  aptitude update
  apt-get install -y ruby ruby-dev libopenssl-ruby rdoc ri irb build-essential wget ssl-cert curl rubygems
  gem install chef --no-ri --no-rdoc --version "#{chef_version}"
fi
BASH
      put script, "/tmp/chef-install.sh", :via => :scp
      run iron_chef.prepare_sudo_cmd("chmod +x /tmp/chef-install.sh")
      run iron_chef.prepare_sudo_cmd("/tmp/chef-install.sh > /tmp/chef-install.log")
    end

    %w(redhat centos).each do |host_os|
      desc "Installs chef via yum on a #{host_os} host."
      task host_os do
        run "mkdir -p #{chef_destination}"
        script = <<-BASH
#!/bin/sh

if type -p chef-solo > /dev/null; then
  echo "Using chef-solo at `which chef-solo`"
else
  yum update -y
  rpm -Uvh http://rbel.frameos.org/rbel6
  yum-config-manager --enable rhel-6-server-optional-rpms
  yum install -y ruby ruby-devel ruby-ri ruby-rdoc ruby-shadow gcc gcc-c++ automake autoconf make curl dmidecode
  cd /tmp
  curl -O http://production.cf.rubygems.org/rubygems/rubygems-1.8.10.tgz
  tar zxf rubygems-1.8.10.tgz
  cd rubygems-1.8.10
  ruby setup.rb --no-format-executable
  gem install chef --no-ri --no-rdoc --version "#{chef_version}"
fi
BASH
        put script, "/tmp/chef-install.sh", :via => :scp
        run iron_chef.prepare_sudo_cmd("chmod +x /tmp/chef-install.sh")
        run iron_chef.prepare_sudo_cmd("/tmp/chef-install.sh > /tmp/chef-install.log")
      end
    end
  end ## end bootstrap namespace ##
end