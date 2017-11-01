require 'nexussw/lxd/driver/cli'

module Kitchen::Driver
  module NexusSW
    class CLI
      include ::NexusSW::LXD::Driver::CLI
    end
  end
end
