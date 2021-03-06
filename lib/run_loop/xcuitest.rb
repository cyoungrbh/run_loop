module RunLoop

  # @!visibility private
  class XCUITest

    require "run_loop/shell"
    include RunLoop::Shell

    class HTTPError < RuntimeError; end

    # @!visibility private
    DEFAULTS = {
      :port => 27753,
      :simulator_ip => "127.0.0.1",
      :http_timeout => RunLoop::Environment.ci? ? 120 : 60,
      :version => "1.0"
    }

    # @!visibility private
    def self.run(options={})
      # logger = options[:logger]
      simctl = options[:sim_control] || options[:simctl] || RunLoop::Simctl.new
      xcode = options[:xcode] || RunLoop::Xcode.new
      instruments = options[:instruments] || RunLoop::Instruments.new

      # Find the Device under test, the App under test, UIA strategy, and reset options
      device = RunLoop::Device.detect_device(options, xcode, simctl, instruments)
      app_details = RunLoop::DetectAUT.detect_app_under_test(options)
      reset_options = RunLoop::Core.send(:detect_reset_options, options)

      app = app_details[:app]
      bundle_id = app_details[:bundle_id]

      if device.simulator? && app
        core_sim = RunLoop::CoreSimulator.new(device, app, :xcode => xcode)
        if reset_options
          core_sim.reset_app_sandbox
        end

        simctl.ensure_software_keyboard(device)
        core_sim.install
      end

      cbx_launcher = XCUITest.detect_cbx_launcher(options, device)

      xcuitest = RunLoop::XCUITest.new(bundle_id, device, cbx_launcher)
      xcuitest.launch
      xcuitest
    end

    # @!visibility private
    #
    # @param [RunLoop::Device] device the device under test
    def self.default_cbx_launcher(device)
      RunLoop::DeviceAgent::XCTestctl.new(device)
    end

    # @!visibility private
    # @param [Hash] options the options passed by the user
    # @param [RunLoop::Device] device the device under test
    def self.detect_cbx_launcher(options, device)
      value = options[:cbx_launcher]
      if value
        if value == :xcodebuild
          RunLoop::DeviceAgent::Xcodebuild.new(device)
        elsif value == :xctestctl
          RunLoop::DeviceAgent::XCTestctl.new(device)
        else
          raise(ArgumentError,
                "Expected :cbx_launcher => #{value} to be :xcodebuild or :xctestctl")
        end
      else
        XCUITest.default_cbx_launcher(device)
      end
    end

    attr_reader :bundle_id, :device, :cbx_launcher

    # @!visibility private
    #
    # The app with `bundle_id` needs to be installed.
    #
    # @param [String] bundle_id The identifier of the app under test.
    # @param [RunLoop::Device] device The device device.
    def initialize(bundle_id, device, cbx_launcher)
      @bundle_id = bundle_id
      @device = device
      @cbx_launcher = cbx_launcher
    end

    # @!visibility private
    def to_s
      "#<XCUITest #{url} : #{bundle_id} : #{device} : #{cbx_launcher}>"
    end

    # @!visibility private
    def inspect
      to_s
    end

    # @!visibility private
    def launch
      start = Time.now
      launch_cbx_runner
      launch_aut
      elapsed = Time.now - start
      RunLoop.log_debug("Took #{elapsed} seconds to launch #{bundle_id} on #{device}")
      true
    end

    # @!visibility private
    def running?
      begin
        health(ping_options)
      rescue => _
        nil
      end
    end

    # @!visibility private
    def stop
      begin
        shutdown
      rescue => _
        nil
      end
    end

    # @!visibility private
    def launch_other_app(bundle_id)
      launch_aut(bundle_id)
    end

    # @!visibility private
    def runtime
      options = http_options
      request = request("device")
      client = client(options)
      response = client.get(request)
      expect_200_response(response)
    end

    # @!visibility private
    def query(mark)
      options = http_options
      parameters = { :id => mark }
      request = request("query", parameters)
      client = client(options)
      response = client.post(request)
      expect_200_response(response)
    end

    # @!visibility private
    def query_for_coordinate(mark)
      body = query(mark)
      coordinate_from_query_result(body)
    end

    # @!visibility private
    def tap_mark(mark)
      coordinate = query_for_coordinate(mark)
      tap_coordinate(coordinate[:x], coordinate[:y])
    end

    # @!visibility private
    def tap_coordinate(x, y, options)
      make_coordinate_gesture_request("touch", x, y)
    end

    # @!visibility private
    def double_tap(x, y)
      make_coordinate_gesture_request("double_tap", x, y)
    end

    # @!visibiity private
    def coordinate_gesture_parameters(name, x, y, options={})
      {
        :gesture => name,
        :specifiers => {
          :coordinate => [x, y]
        },
        :options => options
      }
    end

    # @!visibility private
    def coordinate_gesture_request(name, x, y, gesture_options={})
      parameters = coordinate_gesture_parameters(name, x, y, gesture_options)
      request("gesture", parameters)
    end

    # @!visibility private
    def make_coordinate_gesture_request(name, x, y, options={})
      gesture_options = options.fetch(:gesture_options, {})
      http_options = options.fetch(:http_options, http_options())
      request = coordinate_gesture_request(name, x, y, gesture_options)
      client = client(http_options)
      response = client.post(request)
      expect_200_response(response)
    end

    # @!visibility private
    def rotate_home_button_to(position, sleep_for=1.0)
      orientation = orientation_for_position(position)
      parameters = {
        :orientation => orientation
      }
      request = request("rotate_home_button_to", parameters)
      client = client(http_options)
      response = client.post(request)
      json = expect_200_response(response)
      sleep(sleep_for)
      json
    end

    # @!visibility private
    def perform_coordinate_gesture(gesture, x, y, options={})
      parameters = {
        :gesture => gesture,
        :specifiers => {
          :coordinate => {x: x, y: y}
        },
        :options => options
      }

      RunLoop.log_debug(%Q[
Sending request to perform '#{gesture}' with:

#{JSON.pretty_generate(parameters)}

])
      request = request("gesture", parameters)
      client = client(http_options)
      response = client.post(request)
      expect_200_response(response)
    end

    # @!visibility private
    def coordinate_from_query_result(hash)
      matches = hash["result"]

      if matches.nil? || matches.empty?
        raise "Expected #{hash} to contain some results"
      end

      rect = matches.first["rect"]
      h = rect["height"]
      w = rect["width"]
      x = rect["x"]
      y = rect["y"]

      touchx = x + (w/2.0)
      touchy = y + (h/2.0)

      new_rect = rect.dup
      new_rect[:center_x] = touchx
      new_rect[:center_y] = touchy

      RunLoop.log_debug(%Q[Rect from query:

#{JSON.pretty_generate(new_rect)}

])
      {:x => touchx,
       :y => touchy}
    end

    private

    # @!visibility private
    def xcrun
      RunLoop::Xcrun.new
    end

    # @!visibility private
    def url
      @url ||= lambda do
        if device.simulator?
          "http://#{DEFAULTS[:simulator_ip]}:#{DEFAULTS[:port]}/"
        else
          # This block is untested.
          calabash_endpoint = RunLoop::Environment.device_endpoint
          if calabash_endpoint
            base = calabash_endpoint.split(":")[0..1].join(":")
            "http://#{base}:#{DEFAULTS[:port]}/"
          else
            device_name = device.name.gsub(/['\s]/, "")
            encoding_options = {
              :invalid           => :replace,  # Replace invalid byte sequences
              :undef             => :replace,  # Replace anything not defined in ASCII
              :replace           => ""         # Use a blank for those replacements
            }
            encoded = device_name.encode(::Encoding.find("ASCII"), encoding_options)
            "http://#{encoded}.local:27753/"
          end
        end
      end.call
    end

    # @!visibility private
    def server
      @server ||= RunLoop::HTTP::Server.new(url)
    end

    # @!visibility private
    def client(options={})
      RunLoop::HTTP::RetriableClient.new(server, options)
    end

    # @!visibility private
    def versioned_route(route)
      if ["health", "ping", "sessionIdentifier"].include?(route)
        route
      else
        "#{DEFAULTS[:version]}/#{route}"
      end
    end

    # @!visibility private
    def request(route, parameters={})
      versioned = versioned_route(route)
      RunLoop::HTTP::Request.request(versioned, parameters)
    end

    # @!visibility private
    def ping_options
      @ping_options ||= { :timeout => 0.5, :retries => 1 }
    end

    # @!visibility private
    def http_options
      {
        :timeout => DEFAULTS[:http_timeout],
        :interval => 0.1,
        :retries => (DEFAULTS[:http_timeout]/0.1).to_i
      }
    end

    # @!visibility private
    def session_delete
      options = ping_options
      request = request("delete")
      client = client(options)
      begin
        response = client.delete(request)
        body = expect_200_response(response)
        RunLoop.log_debug("CBX-Runner says, #{body}")
        body
      rescue => e
        RunLoop.log_debug("CBX-Runner session delete error: #{e}")
        nil
      end
    end

    # @!visibility private
    # TODO expect 200 response and parse body (atm the body in not valid JSON)
    def shutdown
      session_delete
      options = ping_options
      request = request("shutdown")
      client = client(options)
      begin
        response = client.post(request)
        body = response.body
        RunLoop.log_debug("CBX-Runner says, \"#{body}\"")
        body
      rescue => e
        RunLoop.log_debug("CBX-Runner shutdown error: #{e}")
        nil
      end
    end

    # @!visibility private
    # TODO expect 200 response and parse body (atm the body is not valid JSON)
    def health(options={})
      merged_options = http_options.merge(options)
      request = request("health")
      client = client(merged_options)
      response = client.get(request)
      body = response.body
      RunLoop.log_debug("CBX-Runner driver says, \"#{body}\"")
      body
    end

    # @!visibility private
    def launch_cbx_runner
      shutdown

      options = {:log_cmd => true}
      exec(["pkill", "xctestctl"], options)
      exec(["pkill", "testmanagerd"], options)
      exec(["pkill", "xcodebuild"], options)

      start = Time.now
      RunLoop.log_debug("Waiting for CBX-Runner to launch...")
      pid = cbx_launcher.launch
      health
      RunLoop.log_debug("Took #{Time.now - start} launch and respond to /health")

      pid
    end

    # @!visibility private
    def launch_aut(bundle_id = @bundle_id)
      client = client(http_options)
      request = request("session", {:bundleID => bundle_id})

      begin
        response = client.post(request)
        RunLoop.log_debug("Launched #{bundle_id} on #{device}")
        RunLoop.log_debug("#{response.body}")
        if device.simulator?
          # It is not clear yet whether we should do this.  There is a problem
          # in the simulator_wait_for_stable_state; it waits too long.
          # device.simulator_wait_for_stable_state
        end
        expect_200_response(response)
      rescue => e
        raise e.class, %Q[Could not launch #{bundle_id} on #{device}:

#{e.message}

Something went wrong.
]
      end
    end

    # @!visibility private
    def response_body_to_hash(response)
      body = response.body
      begin
        JSON.parse(body)
      rescue TypeError, JSON::ParserError => _
        raise RunLoop::XCUITest::HTTPError,
              "Could not parse response '#{body}'; the app has probably crashed"
      end
    end

    # @!visibility private
    def expect_200_response(response)
      body = response_body_to_hash(response)
      if response.status_code < 300 && !body["error"]
        return body
      end

      if response.status_code > 300
        raise RunLoop::XCUITest::HTTPError,
          %Q[Expected status code < 300, found #{response.status_code}.

Server replied with:

#{body}

]
      else
        raise RunLoop::XCUITest::HTTPError,
						%Q[Expected JSON response with no error, but found

#{body["error"]}

]

      end
    end

    # @!visibility private
    def orientation_for_position(position)
      symbol = position.to_sym

      case symbol
        when :down, :bottom
          return 1
        when :up, :top
          return 2
        when :right
          return 3
        when :left
          return 4
        else
          raise ArgumentError, %Q[
Could not coerce '#{position}' into a valid orientation.

Valid values are: :down, :up, :right, :left, :bottom, :top
]
      end
    end
  end
end

