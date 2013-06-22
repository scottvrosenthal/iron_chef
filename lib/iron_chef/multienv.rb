require 'fileutils'

Capistrano::Configuration.instance.load do
  location = fetch(:chef_environment_dir, "environments")

  unless exists?(:chef_environments)
    set :chef_environments, Dir["#{location}/*.rb"].map { |f| File.basename(f, ".rb") }
  end

  chef_environments.each do |name|
    desc "Set the target chef environment to `#{name}'."
    task(name) do
      set :chef_environment, name.to_sym
      load "#{location}/#{chef_environment}" if File.exist?(File.join(location, "#{chef_environment}.rb"))
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

  namespace :multienv do
    desc "[internal] Ensure that a chef environment has been selected."
    task :ensure do
      if !exists?(:chef_environment)
        if exists?(:default_chef_environment)
          logger.important "Defaulting to `#{default_chef_environment}'"
          find_and_execute_task(default_chef_environment)
        else
          abort "No chef environment specified. Please specify one of: #{chef_environments.join(', ')} (e.g. `cap #{chef_environments.first} #{ARGV.last}')"
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
            f.puts "# #{name.upcase}-specific deployment configuration"
          end
        end
      end
    end
  end

  on :start, "multienv:ensure", :except => chef_environments + ['multienv:prepare']

end
