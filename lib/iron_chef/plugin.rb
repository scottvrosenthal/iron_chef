module IronChef
  module Plugin

    def find_node(node_path)
      raise "Node YAML file #{node_path} not found" unless node_path && File.exists?(node_path)

      node_name   = File.basename(node_path).gsub('.yml','')
      node_config = IronChef::ERB.read_erb_yaml(node_path)

      node_config['node_name'] = node_name

      node_config
    end

    def node(node_name)
      nodes_location  = fetch(:chef_nodes_dir, 'nodes')
      unless node_path = Dir.glob("./#{nodes_location}/**/#{node_name}.yml")[0]
        abort "Node '#{node_name}' is unknown. Known nodes are #{nodes_list.join(', ')}."
      end
      find_node(node_path)
    end

    def nodes_list
      nodes_location  = fetch(:chef_nodes_dir, 'nodes')
      nodes_available = Dir.glob("./#{nodes_location}/**/*.yml").map { |f| File.basename(f, '.*') }
      nodes_available.sort
    end

    def env_nodes_list
      location = fetch(:chef_environment_dir, "environments")
      env_nodes_path = Dir.glob("./#{location}/#{chef_environment}.yml")[0]

      raise "Env Node YAML file #{env_nodes_path} not found" unless env_nodes_path && File.exists?(env_nodes_path)

      env_nodes_available = IronChef::ERB.read_erb_yaml(env_nodes_path)
      nodes_available = env_nodes_available['nodes']
      nodes_available.sort
    end

    def tasks_for_env(nodes_names)

      servers = []

      nodes_names.each do |node_name|
        node_config = node(node_name)
        if node_config['server']
          if node_config['server']['host']

            servers << [node_config['server']['host'], node_config['node_name']]

            task(node_config['node_name']) do
              role :server, node_config['server']['host'], { node_name: node_config['node_name'] }
            end

          end
        end
      end

      if nodes_names
        task(:all_nodes) do
          servers.each do |server|
            host_name, node_name = server
            role :server, host_name, { node_name: node_name }
          end
        end
      end

    end

    def upload_node_json(node_name)

      node_config = node(node_name)

      node_dna = {
        :run_list => node_run_list(node_config)
      }.merge(node_config['json'])

      put node_dna.to_json, "#{chef_destination}/node.json", :via => :scp

    end

    def node_run_list(node_config)
      run_list = []
      run_list += node_config['roles'].map   { |r| "role[#{r}]"   } if node_config['roles']
      run_list += node_config['recipes'].map { |r| "recipe[#{r}]" } if node_config['recipes']

      run_list
    end

    def cookbooks
      Array(fetch(:chef_cookbooks) { (:chef_cookbooks).select { |path| File.exist?(path) } })
    end

    def upload_solo_rb
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

    def rsync
      IronChef::Util.thread_pool_size = chef_parallel_rsync_pool_size
      servers = IronChef::Util.optionally_async(find_servers_for_task(current_task), chef_parallel_rsync)
      overrides = {}
      overrides[:user] = fetch(:user, ENV['USER'])
      overrides[:port] = fetch(:port) if exists?(:port)

      failed_servers = servers.map do |server|
        rsync_cmd = IronChef::Rsync.command(
          chef_source,
          IronChef::Rsync.remote_address(server.user || fetch(:user, ENV['USER']), server.host, chef_destination),
          :delete => true,
          :excludes => chef_excludes,
          :ssh => ssh_options.merge(server.options[:ssh_options]||{}).merge(overrides)
        )
        logger.debug rsync_cmd

        server.host unless system rsync_cmd
      end.compact

      raise "rsync failed on #{failed_servers.join(',')}" if failed_servers.any?

      upload_chef_solo_config(servers)
    end

    def upload_chef_solo_config(servers)

      servers.map do |server|
        # allows use to use node aliases for Iron Chef
        node_name = server.options[:node_name]

        raise "upload_chef_solo_config failed on #{server.host} with missing node name on role" unless node_name
        upload_node_json(node_name)

        upload_solo_rb
      end

    end

    def prepare
      run "mkdir -p #{chef_destination}"
      release_chef_client_lock
      run "chown -R $USER: #{chef_destination}"
    end

    def why_run
      chef(:why_run)
    end

    def apply
      chef(:apply)
    end

    def lock
      if should_lock?
        run <<-CHECK_LOCK
if [ -f #{chef_lock_file} ]; then
    stat -c "#{red_text("Chef in progress, #{chef_lock_file} owned by %U since %x")}" #{chef_lock_file} >&2;
    exit 1;
fi
        CHECK_LOCK

        run "touch #{chef_lock_file}"
      end
    end

    def unlock
      run prepare_sudo_cmd("rm -f #{chef_lock_file}; true") if should_lock?
    end

    def release_chef_client_lock
      run prepare_sudo_cmd("rm -f #{chef_destination}/chef-client-running.pid; true")
    end

    def prepare_sudo_cmd(cmd)
      user == 'root' ? cmd : "sudo -- sh -c '#{cmd}'"
    end

    private

    def should_lock?
      chef_lock_file && !ENV['NO_CHEF_LOCK']
    end

    def chef(command = :why_run)
      prepare_chef_cmd = "#{chef_command} #{chef_parameters}"
      chef_cmd = "cd #{chef_destination} && #{chef_command} #{chef_parameters}"
      flag = command == :why_run ? '--why-run' : ''

      writer = if chef_stream_output
                 IronChef::Writer::Streaming.new(logger)
               else
                 IronChef::Writer::Batched.new(logger)
               end

      writer = IronChef::Writer::File.new(writer, chef_write_to_file) unless chef_write_to_file.nil?

      prepared_chef_cmd = prepare_sudo_cmd("#{chef_cmd} #{flag}")
      begin
        run prepared_chef_cmd do |channel, stream, data|
          writer.collect_output(channel[:host], data)
        end
        logger.debug "Chef #{command} complete."
      ensure
        writer.all_output_collected
      end
    end

    def red_text(text)
      "\033[0;31m#{text}\033[0m"
    end
    
  end
end
