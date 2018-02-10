require 'kitchen/transport/base'
require 'kitchen/driver/lxd_version'
require 'shellwords'
require 'fileutils'
require 'pp'

module Kitchen
  module Transport
    class Lxd < Kitchen::Transport::Base
      kitchen_transport_api_version 2

      plugin_version Kitchen::Driver::LXD_VERSION

      def initialize(config = {})
        super
        @cache = {}
      end

      def connection(state)
        begin
          @cache[state[:container_name]] ||= Connection.new nx_transport(state), config.to_hash.merge(state), state_filename
        end.tap { |conn| yield conn if block_given? }
      end

      def nx_transport(state)
        instance.driver.nx_transport state
      end

      def state_filename
        instance.instance_variable_get('@state_file').instance_variable_get('@file_name')
      end

      class Connection < Transport::Base::Connection
        def initialize(transport, options, state_filename)
          super options
          @nx_transport = transport
          @state_filename = state_filename
        end

        attr_reader :nx_transport, :state_filename

        def execute(command)
          return unless command && !command.empty?

          # There are some bash-isms coming from chef_zero (in particular, multiple_converge)
          # so let's wrap it
          command = command.shelljoin if command.is_a? Array
          command = ['bash', '-c', command]

          pp 'Executing command: (prior to su wrap)', command
          res = nx_transport.execute(command, capture: true) do |stdout_chunk, stderr_chunk|
            logger << stdout_chunk if stdout_chunk
            logger << stderr_chunk if stderr_chunk
          end
          res.error!
        end

        def upload(locals, remote)
          nx_transport.execute("mkdir -p #{remote}").error!
          [locals].flatten.each do |local|
            nx_transport.upload_file local, File.join(remote, File.basename(local)) if File.file? local
            if File.directory? local
              debug "Transferring folder (#{local}) to remote: #{remote}"
              nx_transport.upload_folder local, remote
            end
          end
        end

        def download(remotes, local)
          FileUtils.mkdir_p local unless Dir.exist? local
          [remotes].flatten.each do |remote|
            nx_transport.download_folder remote.to_s, local, auto_detect: true
          end
        end

        def login_command
          args = [File.expand_path('../../../../bin/lxc-shell', __FILE__), state_filename]
          LoginCommand.new 'ruby', args
        end
      end
    end
  end
end
