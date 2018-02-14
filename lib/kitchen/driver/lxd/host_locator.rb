require 'kitchen/driver/base'
require 'nexussw/lxd/transport/local'
require 'nexussw/lxd/driver/cli'
require 'nexussw/lxd/driver/rest'

class Kitchen::Driver::Lxd < Kitchen::Driver::Base
  module HostLocator
    def driver
      @driver ||= nx_driver
    end

    def nx_driver
      return ::NexusSW::LXD::Driver::CLI.new(::NexusSW::LXD::Transport::Local.new) unless can_rest?
      ::NexusSW::LXD::Driver::Rest.new(host_address, config[:rest_options])
    end

    def nx_transport(state)
      driver.transport_for(state[:container_name]).tap do |transport|
        transport.user state[:username] if state.key? :username
      end
    end

    def can_rest?
      config[:server] && !config[:server].empty?
    end

    def host_address
      "https://#{config[:server]}:#{config[:port]}"
    end
  end
end
