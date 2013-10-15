require 'socket'
require 'timeout'
require 'thread'
require 'open3'

module Capybara::Touch
  class Connection
    SERVER_PATH = "~/Dropbox/Code/capybara-touch/ios/run"
    # SERVER_PATH = File.expand_path("../../../../bin/webkit_server", __FILE__)
    WEBKIT_SERVER_START_TIMEOUT = 9999

    attr_reader :port

    def initialize(options = {})
      @socket_class = options[:socket_class] || TCPSocket
      if options.has_key?(:stderr)
        @output_target = options[:stderr]
      elsif options.has_key?(:stdout)
        warn "[DEPRECATION] The `stdout` option is deprecated.  Please use `stderr` instead."
        @output_target = options[:stdout]
      else
        @output_target = $stderr
      end
      start_server
      connect
    end

    def puts(string)
      p "PUTS: '#{string}'"
      @socket.puts string
    end

    def print(string)
      p "PUTS: '#{string}'"
      @socket.print string
    end

    def gets
      g = @socket.gets
      p "GETS: #{g.strip}"
      g
    end

    def read(length)
      string = @socket.read(length)
      p "GETS: #{string}"
      string
    end

    private

    def start_server
      @port = 9292
      if (false)
        open_pipe
        discover_port
        forward_output_in_background_thread
      end
    end

    def open_pipe
      _, @pipe_stdout, @pipe_stderr, wait_thr = Open3.popen3(SERVER_PATH)
      @pid = wait_thr[:pid]
      p "Trying to open pipe. pid = #{@pid}"
      register_shutdown_hook
    end

    def register_shutdown_hook
      @owner_pid = Process.pid
      at_exit do
        if Process.pid == @owner_pid
          kill_process
        end
      end
    end

    def kill_process
      if RUBY_PLATFORM =~ /mingw32/
        Process.kill(9, @pid)
      else
        Process.kill("INT", @pid)
      end
    rescue Errno::ESRCH
      # This just means that the webkit_server process has already ended
    end

    def discover_port
      if IO.select([@pipe_stdout], nil, nil, WEBKIT_SERVER_START_TIMEOUT)
        @port = ((@pipe_stdout.first || '').match(/listening on port: (\d+)/) || [])[1].to_i
      end
    end

    def forward_output_in_background_thread
      Thread.new do
        Thread.current.abort_on_exception = true
        IO.copy_stream(@pipe_stderr, @output_target) if @output_target
      end
    end

    def connect
      Timeout.timeout(1000) do
        while @socket.nil?
          attempt_connect
        end
      end
    end

    def attempt_connect
      @socket = @socket_class.open("localhost", @port)
      if defined?(Socket::TCP_NODELAY)
        @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
      end
      p "Connected on port #{@port}"
    rescue Errno::ECONNREFUSED
    end
  end
end