require 'json'
require 'fileutils'

Capistrano::Configuration.instance.load do

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
      run iron_chef.prepare_sudo_cmd("rm -rf #{chef_file_cache_dir}/*")
      iron_chef.unlock
    end

    desc "Shows all nodes available for chef config."
    task :nodes, :except => { :nochef => true } do
      puts iron_chef.nodes_list
    end

    desc "Dump each node's dynamically generated node.json file to local ./tmp/#{chef_nodes_dir} directory."
    task :dump_nodes_json, :except => { :nochef => true } do
      iron_chef.dump_nodes_json
    end

  end ## end chef namespace ##

  ## begin env tasks

  unless exists?(:chef_environments)
    set :chef_environments, Dir["./#{chef_environment_dir}/*.rb"].map { |f| File.basename(f, ".rb") }
  end

  desc "Target individual nodes."
  task :nodes, :except => { :nochef => true }  do

      nodes_available = iron_chef.nodes_list

      iron_chef.tasks_for_env(nodes_available)

  end

  chef_environments.each do |name|
    desc "Set the target chef environment to '#{name}'."
    task name, :except => { :nochef => true }  do
      set :chef_environment, name.to_sym
      if File.exist?(File.join(chef_environment_dir, "#{chef_environment}.rb"))
        load "./#{chef_environment_dir}/#{chef_environment}"

        iron_chef.tasks_for_env(iron_chef.env_nodes_list)

      end
    end
  end

  on :load do
    if chef_environments.include?(ARGV.first)
      # Execute the specified chef environment so that recipes required in environment can contribute to task list
      find_and_execute_task(ARGV.first) if ARGV.any?{ |option| option =~ /-T|--tasks|-e|--explain/ }
    else
      # Execute the default chef environment so that recipes required in environment can contribute tasks
      find_and_execute_task('nodes')
    end
  end

  namespace :env do

    desc "Stub out the chef environment config files."
    task :prepare, :except => { :nochef => true } do
      FileUtils.mkdir_p(chef_environment_dir)
      chef_environments.each do |name|
        rb_env_file = File.join(chef_environment_dir, "#{name}.rb")
        unless File.exists?(rb_env_file)
          File.open(rb_env_file, "w") do |f|
            f.puts "# #{name.upcase}-specific chef environment configuration"
            f.puts "# please put general chef environment config in config/deploy.rb"
          end
          yml_env_node_file = File.join(chef_nodes_dir, "#{name}-server1.yml")
          unless File.exists?(yml_env_node_file)
            File.open(yml_env_node_file, "w") do |f|
              f.puts "json:\n  chef_environment: #{name}\n\nroles:\n  - install_server\n\nrecipes:\n  - commons\n\nserver:\n  host: ec2-xxx-xxx-xxx-xxx.us-west-2.compute.amazonaws.com"
            end
          end
          json_env_data_bag_file = File.join("#{chef_data_bags_dir}/environments", "#{name}.json")
          unless File.exists?(json_env_data_bag_file)
            File.open(json_env_data_bag_file, "w") do |f|
              f.puts "{\n\"id\": \"#{name}\",\n\"description\": \"environments #{name} data_bag_item\"\n}"
            end
          end
          puts "Created chef environment config files for: #{name}"
        end
      end
    end

    desc "Shows chef environment nodes available for chef apply config."
    task :nodes, :except => { :nochef => true } do
      if chef_environments.include?(ARGV.first)
        puts iron_chef.env_nodes_list
      else
        puts iron_chef.nodes_list
      end
    end

  end

  ## end env tasks

  ## begin bootstrap namespace ##

  namespace :bootstrap do

    desc "Installs chef via omnibus on host."
    task :chef, :except => { :nochef => true }  do
      run "mkdir -p #{chef_destination}"

      script = <<-BASH
#!/bin/sh

curl -s -o /tmp/chef-omnibus-install.sh https://www.opscode.com/chef/install.sh
chmod +x /tmp/chef-omnibus-install.sh
/tmp/chef-omnibus-install.sh > /tmp/chef-omnibus-install.log

BASH

      put script, "/tmp/chef-install.sh", :via => :scp
      run iron_chef.prepare_sudo_cmd("chmod +x /tmp/chef-install.sh")
      run iron_chef.prepare_sudo_cmd("/tmp/chef-install.sh > /tmp/chef-install.log")
    end

  end ## end bootstrap namespace ##

  ## begin cookbook namespace ##

  namespace :site_cookbook do

    def create_site_cookbook_stub_dir(site_cookbook_stub_dir)
      if Dir.exists?(site_cookbook_stub_dir)
        site_cookbook_stub_dir = site_cookbook_stub_dir.succ
        create_site_cookbook_stub_dir(site_cookbook_stub_dir)
      else
        FileUtils.mkdir_p(site_cookbook_stub_dir)
        return site_cookbook_stub_dir
      end
    end

    desc "Stub a new chef cookbook in the site-cookbooks folder."
    task :stub, :except => { :nochef => true } do
      site_cookbook_name = 'cookbook_stub001'
      site_cookbook_stub_dir = "#{File.join(chef_site_cookbook_dir, site_cookbook_name)}"
      site_cookbook_stub_dir = create_site_cookbook_stub_dir(site_cookbook_stub_dir)

      default_site_cookbook_folders = %w(attributes recipes templates/default files/default)

      default_site_cookbook_folders.each do |folder|
        FileUtils.mkdir_p(File.join(site_cookbook_stub_dir, folder))
      end

      default_site_cookbook_files = %w(metadata.rb attributes/default.rb recipes/default.rb templates/default/.keep files/default/.keep)

      default_site_cookbook_files.each do |file|
        FileUtils.touch(File.join(site_cookbook_stub_dir, file))
      end

      puts "Created new cookbook stub '#{site_cookbook_stub_dir}' in the site-cookbooks folder."
    end

  end ## end cookbook namespace ##
end