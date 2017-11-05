require 'kitchen/transport/base'
require 'kitchen/driver/lxd_version'

require 'nexussw/lxd/driver/rest'
require 'nexussw/lxd/transport/cli'
require 'nexussw/lxd/transport/rest'
require 'nexussw/lxd/transport/local'

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
        @cache[state[:container_name]] ||= Connection.new nx_transport(state), config.to_hash.merge(state)
        @cache[state[:container_name]].tap { |conn| yield conn if block_given? }
      end

      def can_rest?
        instance.driver.can_rest?
      end

      def nx_driver
        instance.driver.nx_driver
      end

      def nx_transport(state)
        return NexusSW::LXD::Transport::Rest.new nx_driver, state[:container_name] if can_rest?
        NexusSW::LXD::Transport::CLI.new NexusSW::LXD::Transport.Local.new, state[:container_name]
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
          nx_transport.execute "mkdir -p #{remote}", capture: false
          [locals].flatten.each do |local|
            nx_transport.upload_file local, File.join(remote, File.basename(local)) if File.file? local
            upload Dir.entries(local).map { |f| (f == '.' || f == '..') ? nil : File.join(local, f) }.compact, File.join(remote, File.basename(local)) if File.directory? local
          end
        end
      end
    end
  end
end
