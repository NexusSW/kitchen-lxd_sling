
require "kitchen/verifier/base"

class Kitchen::Verifier::Inspec < Kitchen::Verifier::Base
  def runner_options_for_lxd(config_data)
    require "train/lxd"
    return config_data.select { |k, _| [:config, :container_name, :username].include? k }.tap do |data|
      data[:backend] = "lxd"
      data[:logger] = logger
    end
  rescue LoadError
    raise "The `train-lxd` gem is required to run inspec for this container.  Is it installed?"
  end
end
