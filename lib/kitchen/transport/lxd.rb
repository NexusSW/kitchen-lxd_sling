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
          res = nx_transport.execute(command) do |stdout_chunk, stderr_chunk|
            logger << stdout_chunk if stdout_chunk
            logger << stderr_chunk if stderr_chunk
          end
          res.error!
        end

        def upload(locals, remote)
          nx_transport.execute("mkdir -p #{remote}", capture: false).error!
          [locals].flatten.each do |local|
            nx_transport.upload_file local, File.join(remote, File.basename(local)) if File.file? local
            nx_transport.upload_folder local, remote if File.directory? local
          end
        end
      end
    end
  end
end
