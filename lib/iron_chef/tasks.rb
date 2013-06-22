require 'json'
require 'fileutils'

Capistrano::Configuration.instance.load do

  namespace :chef do

    set :chef_version, '=11.4.0'
    set :chef_source, '.'
    set :chef_destination, "/tmp/chef"
    set :chef_cookbooks,   %w(cookbooks)
    set :chef_env_nodes, nil
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

    def tasks_for_node_list

      node_configs = iron_chef.nodes_list.each { |node_name| iron_chef.node(node_name) }

      node_configs.each do |node_config|
        if node_config['server']
          if node_config['server']['public_dns']
            task(node_config['node_name']) { role :server, node_config['server']['public_dns'] }
          end
        end
      end

    end

    desc "Pushes the current chef configuration to the server."
    task :update_code, :except => { :nochef => true } do
      iron_chef.rsync
      generate_node_json
      generate_solo_rb
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
    end

    desc "Shows nodes available for chef config."
    task :nodes, :except => { :nochef => true } do
      puts iron_chef.nodes_list
    end

    #servers = nodes_configs.each do |node_config|
    #  if node_config['server']
    #    if node_config['server']['public_dns']
    #      node_config['server']['public_dns']
    #    end
    #  end
    #end
    #
    #
    #if chef_env_nodes
    #
    #  task(chef_environment) do
    #    role :server, *servers
    #  end
    #
    #  nodes_configs.each do |node_config|
    #    if node_config['server']
    #      if node_config['server']['public_dns']
    #        task(node_config['node_name']) { role :server, node_config['server']['public_dns'] }
    #      end
    #    end
    #  end
    #else
    #  puts "no chef env nodes found"
    #end

    #TODO
    #http://stackoverflow.com/questions/15619945/capistrano-how-to-access-a-serverdefinition-option-in-the-code/15633170#15633170
    def generate_node_json(run_list = [])
      attrs = fetch(:chef_attributes, {})
      if fetch(:default_chef_attributes, true)
        attrs[:application] ||= fetch(:application, nil)
        attrs[:deploy_to] ||= fetch(:deploy_to, nil)
        attrs[:user] ||= fetch(:user, nil)
        attrs[:password] ||= fetch(:password, nil)
        attrs[:main_server] ||= fetch(:main_server, nil)
        attrs[:migrate_env] ||= fetch(:migrate_env, nil)
        attrs[:scm] ||= fetch(:scm, nil)
        attrs[:repository] ||= fetch(:repository, nil)
        attrs[:current_path] ||= current_path
        attrs[:release_path] ||= release_path
        attrs[:shared_path] ||= shared_path
      end
      attrs[:run_list] = run_list
      put attrs.to_json, "#{chef_destination}/node.json", :via => :scp
    end
    
    def cookbooks
      Array(fetch(:chef_cookbooks) { (:chef_cookbooks).select { |path| File.exist?(path) } })
    end    
    
    def generate_solo_rb
      cookbook_paths = cookbooks.map { |c| "File.join(chef_root, #{c.to_s.inspect})" }.join(', ')
      solo_rb = <<-RUBY
      solo true
      chef_root = File.expand_path(File.dirname(__FILE__))
      file_cache_path chef_root
      cookbook_path   [ #{cookbook_paths} ]
      role_path       File.join(chef_root, "roles")
      data_bag_path   File.join(chef_root, "data_bags")
      json_attribs    File.join(chef_root, "node.json")
      log_level "#{chef_log_level}".to_sym
      RUBY
      put solo_rb, "#{chef_destination}/solo.rb", :via => :scp
    end

    ## begin multi environments ##

    location = fetch(:chef_environment_dir, "environments")

    unless exists?(:chef_environments)
      set :chef_environments, Dir["#{location}/*.rb"].map { |f| File.basename(f, ".rb") }
    end

    chef_environments.each do |name|
      desc "Set the target chef environment to '#{name}'."
      task(name) do
        set :chef_environment, name.to_sym
        if File.exist?(File.join(location, "#{chef_environment}.rb"))
          load "#{location}/#{chef_environment}"
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
        FileUtils.mkdir_p(location)
        chef_environments.each do |name|
          file = File.join(location, name + ".rb")
          unless File.exists?(file)
            File.open(file, "w") do |f|
              f.puts "# #{name.upcase}-specific chef environment configuration"
              f.puts "# please put general deployment config in config/deploy.rb"
              f.puts "# map chef env nodes to node.yml per environment (e.g. '#{name.upcase}-web1.yml #{name.upcase}-app1.yml #{name.upcase}-db1.yml')"
              f.puts "# set :chef_env_nodes, %w(#{name.upcase}-web1 #{name.upcase}-app1 #{name.upcase}-db1)"
            end
          end
        end
      end
    end

    on :start, "chef:env:ensure", :except => chef_environments + ['chef:env:prepare']

    ## end multi environments ##

    ## begin bootstrap namespace ##

    namespace :bootstrap do

      desc "Installs chef via apt on an ubuntu host."
      task :ubuntu do
        run "mkdir -p #{chef_destination}"
        script = <<-BASH
        if type -p chef-solo > /dev/null; then
          echo "Using chef-solo at `which chef-solo`"
        else
          aptitude update
          apt-get install -y ruby ruby-dev libopenssl-ruby rdoc ri irb build-essential wget ssl-cert curl rubygems
          gem install chef --no-ri --no-rdoc --version "#{chef_version}"
        fi
        BASH
        put script, "/tmp/chef-install.sh", :via => :scp
        run iron_chef.prepare_sudo_cmd("/tmp/chef-install.sh > /tmp/chef-install.log")
      end

      %w(redhat centos).each do |host_os|
        desc "Installs chef via yum on a #{host_os} host."
        task host_os do
          run "mkdir -p #{chef_destination}"
          script = <<-BASH
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
          run iron_chef.prepare_sudo_cmd("/tmp/chef-install.sh > /tmp/chef-install.log")
        end
      end

    end ## end bootstrap namespace ##

  end ## end chef namespace ##

end