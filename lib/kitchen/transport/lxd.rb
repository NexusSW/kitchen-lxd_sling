require 'kitchen/transport/base'
require 'kitchen/driver/lxd_version'

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
          @cache[state[:container_name]] ||= Connection.new nx_transport(state), config.to_hash.merge(state)
        end.tap { |conn| yield conn if block_given? }
      end

      def nx_transport(state)
        instance.driver.nx_transport state
      end

      class Connection < Transport::Base::Connection
        def initialize(transport, options)
          super options
          @nx_transport = transport
        end

        attr_reader :nx_transport

        def execute(command)
          return unless command && !command.empty?
          res = nx_transport.execute(command, capture: true) do |stdout_chunk, stderr_chunk|
            logger.info stdout_chunk if stdout_chunk
            logger.info stderr_chunk if stderr_chunk
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

        # TODO: implement download_folder in lxd-common
        def download(_remotes, _local)
          raise ClientError, "#{self.class}#download must be implemented"
        end

        # TODO: wrap this in bash -c '' if on windows with WSL and ENV['TERM'] is not set - and accept a :disable_wsl transport config option
        def login_command
          args = [options[:container_name]]
          if options[:config][:server]
            args <<= options[:config][:server]
            args <<= options[:config][:port].to_s
            args <<= options[:config][:rest_options][:verify_ssl].to_s if options[:config][:rest_options].key?(:verify_ssl)
          end
          LoginCommand.new 'lxc-shell', args
        end
      end
    end
  end
end
