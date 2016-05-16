# -*- encoding: utf-8 -*-

ruby_files = Dir.glob('{lib}/**/*.rb')
java_scripts = Dir.glob('scripts/**/*.js')
bash_scripts = ['scripts/udidetect', 'scripts/read-cmd.sh', 'scripts/timeout3']
plists = Dir.glob('plists/**/*.plist')

Gem::Specification.new do |s|
  s.name        = 'run_loop'

  s.version     = lambda do
    file = File.join("lib", "run_loop", "version.rb")
    m = Module.new
    m.module_eval IO.read(file).force_encoding("utf-8")
    version = m::RunLoop::VERSION
    unless /(\d+\.\d+\.\d+(\.pre\d+)?)/.match(version)
      raise %Q{
Could not parse constant RunLoop::VERSION: '#{version}'
into a valid version, e.g. 1.2.3 or 1.2.3.pre10
      }
    end
    version
  end.call

  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Karl Krukow']
  s.email       = ['karl.krukow@xamarin.com']
  s.homepage    = 'http://calaba.sh'
  s.summary     = %q{The bridge between Calabash iOS and Xcode command-line
tools like instruments and simctl.}
  s.files         = ruby_files + java_scripts + bash_scripts + plists + ['LICENSE']
  s.require_paths = ['lib']
  s.licenses    = ['MIT']
  s.executables = 'run-loop'

  s.required_ruby_version = '>= 2.0'

  s.add_dependency('json', '~> 1.8')
  s.add_dependency('awesome_print', '~> 1.2')
  s.add_dependency('CFPropertyList','~> 2.2')
  s.add_dependency('thor', '>= 0.18.1', '< 1.0')
  s.add_dependency('command_runner_ng', '>= 0.0.2')
  s.add_dependency("httpclient", "~> 2.6")
  s.add_dependency("dnssd", "~> 3.0")

  s.add_development_dependency("rspec_junit_formatter", "~> 0.2")
  s.add_development_dependency("luffa", "~> 2.0")
  s.add_development_dependency('bundler', '~> 1.6')
  s.add_development_dependency('travis', '~> 1.8')
  s.add_development_dependency('rspec', '~> 3.0')
  s.add_development_dependency('rake', '~> 10.3')
  s.add_development_dependency('guard-rspec', '~> 4.3')
  s.add_development_dependency('guard-bundler', '~> 2.0')
  # Pin to 3.0.6; >= 3.1.0 requires ruby 2.2. This is guard dependency.
  s.add_development_dependency("listen", "3.0.6")
  s.add_development_dependency('growl', '~> 1.0')
  s.add_development_dependency('stub_env', '>= 1.0.1', '< 2.0')
  s.add_development_dependency('pry')
  s.add_development_dependency('pry-nav')
end
