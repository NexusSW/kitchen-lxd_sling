require 'kitchen'
require 'kitchen/driver/base'
require 'kitchen/driver/nexussw/cli'
require 'kitchen/driver/nexussw/rest'
require 'kitchen/transport/lxd/local'

require 'pp'

module Kitchen
  module Driver
    class LXD < Kitchen::Driver::Base
      def initialize(config = {})
        pp 'Config:', config
        super config
        @driver = driver_for config
      end

      attr_reader :driver

      kitchen_driver_api_version 2

      default_config :hostname, nil
      default_config :port, 8443
      default_config :rest_options, {}

      def create(state)
        pp 'State (create):', state
      end

      def destroy(state)
        pp 'State (destroy):', state
      end

      private

      def can_rest?
        !config[:hostname].nil?
      end

      def host_address
        "https://#{config[:hostname]}:#{config[:port]}"
      end

      def driver_for(config)
        return NexusSW::CLI.new(Transport::LXD::Local.new) unless can_rest?
        NexusSW::Rest.new(host_address, config[:rest_options])
      end
    end
  end
end

require 'kitchen/driver/lxd/version'
