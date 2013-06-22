module IronChef
  module Plugin

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
    end

    def prepare
      run "mkdir -p #{chef_destination}"
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

    def prepare_sudo_cmd(cmd)
      user == 'root' ? cmd : "sudo -- sh -c '#{cmd}'"
    end

    private

    def should_lock?
      chef_lock_file && !ENV['NO_CHEF_LOCK']
    end

    def chef(command = :why_run)
      prepare_chef_cmd = prepare_sudo_cmd("#{chef_command} #{chef_parameters}")
      chef_cmd = "cd #{chef_destination} && #{prepare_chef_cmd}"
      flag = command == :why_run ? '--why-run' : ''

      writer = if chef_stream_output
                 IronChef::Writer::Streaming.new(logger)
               else
                 IronChef::Writer::Batched.new(logger)
               end

      writer = IronChef::Writer::File.new(writer, chef_write_to_file) unless chef_write_to_file.nil?

      begin
        run "#{chef_cmd} #{flag}" do |channel, stream, data|
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
