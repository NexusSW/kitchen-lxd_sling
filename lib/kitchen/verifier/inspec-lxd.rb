
require 'kitchen/verifier/base'
require 'pp'

class Kitchen::Verifier::Inspec < Kitchen::Verifier::Base
  def runner_options_for_lxd(config_data)
    config_data.tap do
      pp config_data
    end
  end
end
