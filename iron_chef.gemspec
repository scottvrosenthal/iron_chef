# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'iron_chef/version'

Gem::Specification.new do |gem|
  gem.name          = "iron_chef"
  gem.platform      = Gem::Platform::RUBY
  gem.version       = IronChef::VERSION
  gem.license       = "MIT"

  gem.required_ruby_version = '>= 1.9.3'
  gem.required_rubygems_version = '>= 1.8.11'

  gem.authors       = ["Scott Rosenthal"]
  gem.email         = ["sr7575@gmail.com"]
  gem.description   = %q{Iron Chef is a lightweight Chef Solo wrapper built as a capistrano plugin}
  gem.summary       = %q{Iron Chef makes cloud server provisioning with Chef Solo powerful and easy.}
  gem.homepage      = "https://github.com/scottvrosenthal/iron_chef"
  gem.license       = "MIT"
  gem.files         = `git ls-files | grep -vE '(jenkins|.travis.yml|.gitmodules|.gitignore|.ruby-version|.ruby-gemset|README.md)'`.split("\n")
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency 'capistrano', '>= 2.15.4'
  gem.add_dependency 'json'

end
