$LOAD_PATH << File.expand_path(File.dirname(__FILE__))

require 'iron_chef/rsync'
require 'iron_chef/async_enumerable'
require 'iron_chef/erb'
require 'iron_chef/plugin'
require 'iron_chef/thread_pool'
require 'iron_chef/util'
require 'iron_chef/writer/batched'
require 'iron_chef/writer/file'
require 'iron_chef/writer/streaming'
require 'iron_chef/tasks'

Capistrano.plugin :iron_chef, IronChef::Plugin