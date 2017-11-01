require 'nexussw/lxd/transport/local'

module Kitchen::Transport
  module LXD
    class Local
      include NexusSW::LXD::Transport::Local
    end
  end
end
