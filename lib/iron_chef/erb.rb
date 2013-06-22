require 'erb'
require 'yaml'
require 'json'

module IronChef
  module ERB
    def self.read_erb(path)
      ::ERB.new(File.read(path)).result binding
    end

    def self.read_erb_yaml(path)
      YAML::load(read_erb path)
    end

    def self.read_erb_json(path)
      JSON::parse(read_erb path)
    end
  end
end