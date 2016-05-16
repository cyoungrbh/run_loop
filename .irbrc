require 'irb/completion'
require 'irb/ext/save-history'
require 'benchmark'
require 'run_loop'
require 'command_runner'
require "dnssd"

AwesomePrint.irb!

ARGV.concat [ '--readline',
              '--prompt-mode',
              'simple']

IRB.conf[:SAVE_HISTORY] = 100
IRB.conf[:HISTORY_FILE] = '.irb-history'

IRB.conf[:AUTO_INDENT] = true

IRB.conf[:PROMPT][:RUN_LOOP] = {
  :PROMPT_I => "run-loop #{RunLoop::VERSION}> ",
  :PROMPT_N => "run-loop #{RunLoop::VERSION}> ",
  :PROMPT_S => nil,
  :PROMPT_C => "> ",
  :AUTO_INDENT => false,
  :RETURN => "%s\n"
}

IRB.conf[:PROMPT_MODE] = :RUN_LOOP

begin
  require 'pry'
  Pry.config.history.should_save = false
  Pry.config.history.should_load = false
  require 'pry-nav'
rescue LoadError => _

end

spec_resources = './spec/resources.rb'
print "require '#{spec_resources}'..."
require spec_resources
puts 'done!'

puts ''
puts '#       =>  Useful Methods  <=          #'
puts '> xcode       => Xcode instance'
puts '> instruments => Instruments instance'
puts '> simctl  => Simctl instance'
puts '> default_sim => Default simulator'
puts '> verbose     => turn on DEBUG logging'
puts '> quiet       => turn off DEBUG logging'
puts ''

def xcode
  @xcode ||= RunLoop::Xcode.new
end

def instruments
  @instruments ||= RunLoop::Instruments.new
end

def simctl
  @simctl ||= RunLoop::Simctl.new
end

def default_sim
  @default_sim ||= lambda do
    name = RunLoop::Core.default_simulator(xcode)
    simctl.simulators.find do |sim|
      sim.instruments_identifier(xcode) == name
    end
  end.call
end

def verbose
  ENV['DEBUG'] = '1'
end

def quiet
  ENV['DEBUG'] = '1'
end

def create_simulator(n, options={})
  default_options = {
    :name => 'tester',
    :type => 'iPhone 6',
    :runtime => 'com.apple.CoreSimulator.SimRuntime.iOS-9-0'
  }

  merged_options = default_options.merge(options)

  name = merged_options[:name]
  type = merged_options[:type]
  runtime = merged_options[:runtime]

  n.times do
    system('xcrun', 'simctl', 'create', name, type, runtime)
  end
end

def delete_simulator(name)
  simctl.simulators.each do |simulator|
    if simulator.name == name
      puts "Deleting #{simulator}"
      system('xcrun', 'simctl', 'delete', simulator.udid)
    end
  end
  true
end

if !ENV["CBXWS"]
  moody = File.expand_path(File.join("~/", "git", "calabash", "xcuitest", "CBXDriver.xcworkspace"))
  prometus = File.expand_path(File.join("~/", "calabash-xcuitest-server", "CBXDriver.xcworkspace"))

  if File.directory?(moody)
    ENV["CBXWS"] = moody
  elsif File.directory?(prometus)
    ENV["CBXWS"] = prometus
  end
end

puts "XCUITest workspace = #{ENV["CBXWS"]}"

def xcuitest(bundle_id="com.apple.Preferences")
  device = RunLoop::Device.detect_device({}, xcode, simctl, instruments)
  RunLoop::XCUITest.new(bundle_id, device)
end

def holmes(bundle_id="com.apple.Preferences")
  device = RunLoop::Device.detect_device({}, xcode, simctl, instruments)
  options = {
    :device => device.udid,
    :xcuitest => true,
    :xcode => xcode,
    :simctl => simctl,
    :instruments => instruments,
    :app => bundle_id
  }
  RunLoop.run(options)
end

verbose

motd=["Let's get this done!", 'Ready to rumble.', 'Enjoy.', 'Remember to breathe.',
      'Take a deep breath.', "Isn't it time for a break?", 'Can I get you a coffee?',
      'What is a calabash anyway?', 'Smile! You are on camera!', 'Let op! Wild Rooster!',
      "Don't touch that button!", "I'm gonna take this to 11.", 'Console. Engaged.',
      'Your wish is my command.', 'This console session was created just for you.']
puts "#{motd.sample()}"

