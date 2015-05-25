Gem::Specification.new do |s|
  s.name        = 'zendesk_apps_tools'
  s.version     = '1.22.6'
  s.executables << 'zat'
  s.platform    = Gem::Platform::RUBY
  s.license     = 'Apache License Version 2.0'
  s.authors     = ['James A. Rosen', 'Kenshiro Nakagawa', 'Shajith Chacko', 'Likun Liu']
  s.email       = ['dev@zendesk.com']
  s.homepage    = 'http://github.com/zendesk/zendesk_apps_tools'
  s.summary     = 'Tools to help you develop Zendesk Apps.'
  s.description = s.summary

  s.required_ruby_version = '>= 2.0'
  s.required_rubygems_version = '>= 1.3.6'

  s.add_runtime_dependency 'thor',        '~> 0.18.0'
  s.add_runtime_dependency 'rubyzip',     '~> 0.9.1'
  s.add_runtime_dependency 'sinatra',     '~> 1.3.4'
  s.add_runtime_dependency 'faraday',     '~> 0.8.7'
  s.add_runtime_dependency 'zendesk_apps_support', '~> 1.17.3'

  s.add_development_dependency 'cucumber'
  s.add_development_dependency 'aruba'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'bump'
  s.add_development_dependency 'webmock'

  s.files        = Dir.glob('{bin,lib,app_template,templates}/**/*') + %w(README.md LICENSE)
  s.test_files   = Dir.glob('features/**/*')
  s.require_path = 'lib'
end
