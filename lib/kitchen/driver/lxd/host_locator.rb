require 'kitchen/driver/base'

class Kitchen::Driver::Lxd < Kitchen::Driver::Base
  module HostLocator
    def nx_driver
      return NexusSW::LXD::Driver::CLI.new(NexusSW::LXD::Transport::Local.new) unless can_rest?
      info 'Utilizing REST interface at ' + host_address
      NexusSW::LXD::Driver::Rest.new(host_address, config[:rest_options])
    end

    def nx_transport(state)
      driver.transport_for state[:container_name]
    end

    def can_rest?
      !config[:server].nil?
    end

    def host_address
      "https://#{config[:server]}:#{config[:port]}"
    end
  end
end
