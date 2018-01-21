require 'kitchen'
require 'kitchen/driver/base'
require 'kitchen/transport/lxd'
require 'kitchen/driver/lxd_version'
require 'kitchen/driver/lxd/host_locator'

require 'nexussw/lxd/driver/cli'
require 'nexussw/lxd/driver/rest'
require 'nexussw/lxd/transport/cli'
require 'nexussw/lxd/transport/rest'
require 'nexussw/lxd/transport/local'

require 'securerandom'

require 'pp'

module Kitchen
  module Driver
    class Lxd < Kitchen::Driver::Base
      include HostLocator

      def initialize(config = {})
        # pp 'Config:', config
        super
      end

      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::LXD_VERSION

      default_config :server, nil
      default_config :port, 8443
      default_config :image_server, 'https://images.linuxcontainers.org'
      default_config :rest_options, {}

      def create(state)
        state[:config] = config.slice :server, :port, :rest_options, :image_server
        info 'Utilizing REST interface at ' + host_address if respond_to?(:info) && can_rest?

        state[:container_name] = new_container_name unless state[:container_name]

        # TODO: convergent behavior on container_options change? (:profiles :config)
        state[:container_options] = container_options

        info "Container name: #{state[:container_name]}"
        driver.create_container(state[:container_name], state[:container_options])

        # Allow SSH transport on known images with sshd enabled
        # This will only work if the container is routable.  LXD does not do port forwarding (yet)
        # Which also means that you might need to do 'ssh_login: false' in the config if you're using a cloud-image and aren't routable
        # think ahead for default behaviour once LXD can port forward
        # FUTURE: If I get time I'll look into faking a port forward with something under /dev/ until then
        if use_ssh?
          # Normalize [:ssh_login]
          config[:ssh_login] = { username: config[:ssh_login] } if config[:ssh_login].is_a? String
          config[:ssh_login] = {} if config[:ssh_login] && !config.to_hash[:ssh_login].is_a?(Hash)

          state[:username] = config[:ssh_login][:username] if config[:ssh_login]
          state[:username] ||= 'root'
          # TODO: make public key configurable
          info 'Waiting for an IP address...'
          state[:ip_address] = state[:hostname] = container_ip(state)
          setup_ssh(state[:username], "#{ENV['HOME']}/.ssh/id_rsa.pub", state)
          info "SSH access enabled on #{state[:ip_address]}"
        else
          # TODO: this section is only for the base images on linuxcontainers.org... (and I still need to account for yum)
          # they need patched because they don't have wget, or anything else with which to download the chef client
          # Custom images should account for this, so I won't run this patch for them (in the name of testing speed)
          info 'Waiting for network access...'
          state[:ip_address] = container_ip(state) # This is only here to wait until the net is up so we can download packages
          unless cloud_image?
            info 'Installing additional dependencies...'
            nx_transport(state).execute('apt-get install openssl wget ca-certificates -y').error!
          end
        end
      end

      def finalize_config!(instance)
        super.tap do
          instance.transport = Kitchen::Transport::Lxd.new config unless lxd_transport_selected? || use_ssh?
        end
      end

      def destroy(state)
        info "Destroying container #{state[:container_name]}"
        driver.delete_container state[:container_name]
      end

      private

      # ssh is kitchen's default unless lxd is selected by the user
      # otherwise, only use ssh when the user supplies info
      # and automatically, only on capable cloud images (requires kitchen 1.19 to perform the automatic override)
      def use_ssh?
        return false if lxd_transport_selected?
        return true if config[:ssh_login]
        return false if config[:ssh_login] == false # allow forced disable for cloud-images... or (TODO: should I not default enable for them?)
        cloud_image?
      end

      # if selected by user during startup (finalize_config!)
      # later, if selected by the user, or if deemed necessary by the driver
      def lxd_transport_selected?
        instance.transport.is_a? Kitchen::Transport::Lxd
      end

      def cloud_image?
        server = image_server
        return false unless server && server[:server]
        server[:server].downcase.start_with? 'https://cloud-images.ubuntu.com'
      end

      def new_container_name
        instance.name + '-' + SecureRandom.hex(8)
      end

      # Normalize into a hash with the correct protocol
      # We'll take a given hash verbatim
      # But we'll allow a simple string to default to the simplestreams protocol if no port is specified
      # (otherwise 'lxd' is default, but counterintuitive given that if we specify neither a port nor a protocol, 8443 will be appended for lxd's default)
      # Side effect: differing behavior (protocol) depending on whether a port is specified on a simple string
      #   which is (ok?)  If you want to specify an odd port, you should probably also specify which protocol
      def image_server
        server = config[:image_server]
        if server.is_a? String
          server = { server: server }
          server[:protocol] = 'simplestreams' if server[:server].split(':', 3)[2].nil?
        end
        server
      end

      # Special cases:  using example `ubuntu-16.04`
      #   0: if alias, fingerprint, or properties are specified, use instead of the below: (handled by caller)
      #   1: if server.start_with? 'https://cloud-images.ubuntu.com'
      #       - trim the leading `ubuntu-` (optionally specified)
      #   2: if server.start_with? 'https://images.linuxcontainers.org'
      #       - replace `-` with `/` (in all cases?)
      #       - replace version with codename, if dist == 'ubuntu'
      def image_name(server)
        name = instance.platform.name
        return name unless server

        # 1:
        if server.downcase.start_with? 'https://cloud-images.ubuntu.com'
          info "Using cloud-image '#{name}'"
          return name.downcase.sub(/^ubuntu-/, '')
        end
        # 2:
        if server.downcase.start_with? 'https://images.linuxcontainers.org'
          name = name.downcase.split('-')
          # 'core' parses out in this method as the 'version' so just use 'ubuntu-core' in the kitchen.yml
          if UBUNTU_RELEASES.key?(name[1]) && name[0] == 'ubuntu'
            name[1] = UBUNTU_RELEASES[name[1]]
            name[0] = 'ubuntu-core' if name[1] == '16' # Logic patch for the edge case.  We'll do something different if this gets complicated
          end
          name = name.join('/')
          info "Using standard image #{name}"
        end
        name
      end

      # only bothering with the releases on linuxcontainers.org
      # leaving this mutable so that end-users can append new releases to it
      # Usage Note: If a future release is not in the below table, just specify the full image name in the kitchen yml instead of using ubuntu-<version>
      UBUNTU_RELEASES = { # rubocop:disable Style/MutableConstant
        '12.04' => 'precise',
        '14.04' => 'trusty',
        '16.04' => 'xenial',
        '17.04' => 'zesty',
        '17.10' => 'artful',
        '18.04' => 'bionic',
        'core' => '16',
      }

      def container_options
        options = image_server
        # 0:
        found = false
        %w(:alias :fingerprint :properties).each do |k|
          if config.key? k
            options[k] = config[k]
            found = true
          end
        end
        options[:alias] = image_name(options[:server]) unless found
        options.merge config.slice(:profiles, :config)
      end

      def setup_ssh(username, pubkey, state)
        # DEFERRED: should I create the ssh user if it doesn't exist? (I've seen that in other drivers)
        # not for now...  that is an edge case within an edge case, and the default case just shells in as 'root' without concept of 'users'
        # submit a feature request if you need me to create a user
        # and that is if it is unfeasible for you to create a custom image with that user included
        return if state[:ssh_enabled]
        raise ActionFailed, "Public Key File does not exist (#{pubkey})" unless File.exist? pubkey

        transport = nx_transport(state)
        remote_file = "/tmp/#{state[:container_name]}-publickey"
        transport.upload_file pubkey, remote_file
        begin
          sshdir = transport.execute("bash -c \"grep '^#{username}:' /etc/passwd | cut -d':' -f 6\"").error!.stdout.strip
        rescue => e
          fatal "Transport Error querying SSH User: #{sshdir}\n#{e.message}"
          raise
        ensure
          raise ActionFailed, "User (#{username}), or their home directory, were not found within container (#{state[:container_name]})" unless sshdir && !sshdir.empty?
          sshdir += '/.ssh'
        end
        ak_file = sshdir + '/authorized_keys'

        info "Inserting public key for container user '#{username}'"
        transport.execute("bash -c 'mkdir -p #{sshdir} 2> /dev/null; cat #{remote_file} >> #{ak_file} \
          && rm -rf #{remote_file} && chown -R #{username}:#{username} #{sshdir}'").error! # , capture: false
        state[:ssh_enabled] = true
      end

      def container_ip(state)
        # TODO: make timeout configurable
        driver.wait_for state[:container_name], :ip # , 60 # default timeout=60
      end
    end
  end
end

=begin
"Instance:"
#<Kitchen::Instance:0x48b5350
 @driver=
  #<Kitchen::Driver::LXD:0x490e9f0
   @config=
    {:name=>"LXD",
     :hostname=>"wyzsrv",
     :rest_options=>{:verify_ssl=>false},
     :"image-server"=>
      {:addr=>"https://cloud-images.ubuntu.com/releases",
       :protocol=>"simplestreams"},
     :kitchen_root=>"C:/Users/Sean/Documents/projects/kitchen-lxd_nexus",
     :test_base_path=>
      "C:/Users/Sean/Documents/projects/kitchen-lxd_nexus/test/integration",
     :log_level=>:info,
     :port=>8443},
   @driver=
    #<NexusSW::LXD::Driver::Rest:0x490c200
     @driver_options={:verify_ssl=>false},
     @hk=
      #<Hyperkit::Client:0x490c170
       @api_endpoint="https://wyzsrv:8443",
       @auto_sync=true,
       @client_cert="C:/Users/Sean/.config/lxc/client.crt",
       @client_key="C:/Users/Sean/.config/lxc/client.key",
       @default_media_type="application/json",
       @middleware=
        #<Faraday::RackBuilder:0x49fadf0
         @handlers=
          [Hyperkit::Middleware::FollowRedirects,
           Hyperkit::Response::RaiseError,
           Faraday::Adapter::NetHttp]>,
       @proxy=nil,
       @user_agent="Hyperkit Ruby Gem 1.1.0",
       @verify_ssl=false>,
     @rest_endpoint="https://wyzsrv:8443">,
   @instance=#<Kitchen::Instance:0x48b5350 ...>>,
 @logger=
  #<Kitchen::Logger:0x4907d48
   @log_overwrite=true,
   @logdev=
    #<Kitchen::Logger::LogdevLogger:0x4907a90
     @default_formatter=#<Logger::Formatter:0x4907a60 @datetime_format=nil>,
     @formatter=nil,
     @level=1,
     @logdev=
      #<Logger::LogDevice:0x4907a30
       @dev=
        #<File:C:/Users/Sean/Documents/projects/kitchen-lxd_nexus/.kitchen/logs/default-ubuntu-1604.log>,
       @filename=nil,
       @mon_count=0,
       @mon_mutex=#<Thread::Mutex:0x4907a00>,
       @mon_owner=nil,
       @shift_age=nil,
       @shift_period_suffix=nil,
       @shift_size=nil>,
     @progname="default-ubuntu-1604">,
   @loggers=
    [#<Kitchen::Logger::LogdevLogger:0x4907a90
      @default_formatter=#<Logger::Formatter:0x4907a60 @datetime_format=nil>,
      @formatter=nil,
      @level=1,
      @logdev=
       #<Logger::LogDevice:0x4907a30
        @dev=
         #<File:C:/Users/Sean/Documents/projects/kitchen-lxd_nexus/.kitchen/logs/default-ubuntu-1604.log>,
        @filename=nil,
        @mon_count=0,
        @mon_mutex=#<Thread::Mutex:0x4907a00>,
        @mon_owner=nil,
        @shift_age=nil,
        @shift_period_suffix=nil,
        @shift_size=nil>,
      @progname="default-ubuntu-1604">,
     #<Kitchen::Logger::StdoutLogger:0x49079d0
      @default_formatter=#<Logger::Formatter:0x49079a0 @datetime_format=nil>,
      @formatter=
       #<Proc:0x49078e0@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/logger.rb:296>,
      @level=1,
      @logdev=
       #<Logger::LogDevice:0x4907970
        @dev=#<IO:<STDOUT>>,
        @filename=nil,
        @mon_count=0,
        @mon_mutex=#<Thread::Mutex:0x4907940>,
        @mon_owner=nil,
        @shift_age=nil,
        @shift_period_suffix=nil,
        @shift_size=nil>,
      @progname="default-ubuntu-1604">]>,
 @name="default-ubuntu-1604",
 @platform=
  #<Kitchen::Platform:0x3c840d8
   @name="ubuntu-16.04",
   @os_type="unix",
   @shell_type="bourne">,
 @provisioner=
  #<Kitchen::Provisioner::ChefSolo:0x4964b20
   @config=
    {:name=>"chef_solo",
     :kitchen_root=>"C:/Users/Sean/Documents/projects/kitchen-lxd_nexus",
     :test_base_path=>
      "C:/Users/Sean/Documents/projects/kitchen-lxd_nexus/test/integration",
     :http_proxy=>nil,
     :https_proxy=>nil,
     :ftp_proxy=>nil,
     :retry_on_exit_code=>[],
     :max_retries=>1,
     :wait_for_retry=>30,
     :root_path=>
      #<Proc:0x395f1d8@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/base.rb:36>,
     :sudo=>
      #<Proc:0x395f1c0@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/base.rb:40>,
     :sudo_command=>
      #<Proc:0x395f1a8@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/base.rb:44>,
     :command_prefix=>nil,
     :require_chef_omnibus=>true,
     :chef_omnibus_url=>"https://omnitruck.chef.io/install.sh",
     :chef_omnibus_install_options=>nil,
     :run_list=>[],
     :attributes=>{},
     :config_path=>nil,
     :log_file=>nil,
     :log_level=>"auto",
     :profile_ruby=>false,
     :policyfile=>nil,
     :policyfile_path=>nil,
     :always_update_cookbooks=>false,
     :cookbook_files_glob=>
      "README.*,metadata.{json,rb},attributes/**/*,definitions/**/*,files/**/*,libraries/**/*,providers/**/*,recipes/**/*,resources/**/*,templates/**/*",
     :deprecations_as_errors=>false,
     :multiple_converge=>1,
     :enforce_idempotency=>false,
     :data_path=>
      #<Proc:0x4965780@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/chef_base.rb:74>,
     :data_bags_path=>
      #<Proc:0x49656f0@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/chef_base.rb:79>,
     :environments_path=>
      #<Proc:0x49656d8@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/chef_base.rb:84>,
     :nodes_path=>
      #<Proc:0x49656c0@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/chef_base.rb:89>,
     :roles_path=>
      #<Proc:0x49656a8@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/chef_base.rb:94>,
     :clients_path=>
      #<Proc:0x4965690@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/chef_base.rb:99>,
     :encrypted_data_bag_secret_key_path=>
      #<Proc:0x4965678@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/chef_base.rb:104>,
     :solo_rb=>{},
     :chef_solo_path=>
      #<Proc:0x4964fd0@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/provisioner/chef_solo.rb:33>},
   @instance=#<Kitchen::Instance:0x48b5350 ...>>,
 @state_file=
  #<Kitchen::StateFile:0x48b5440
   @file_name=
    "C:/Users/Sean/Documents/projects/kitchen-lxd_nexus/.kitchen/default-ubuntu-1604.yml">,
 @suite=
  #<Kitchen::Suite:0x3c84198 @excludes=[], @includes=[], @name="default">,
 @transport=
  #<Kitchen::Transport::Ssh:0x48fc090
   @config=
    {:name=>"ssh",
     :kitchen_root=>"C:/Users/Sean/Documents/projects/kitchen-lxd_nexus",
     :test_base_path=>
      "C:/Users/Sean/Documents/projects/kitchen-lxd_nexus/test/integration",
     :log_level=>:info,
     :port=>22,
     :username=>"root",
     :keepalive=>true,
     :keepalive_interval=>60,
     :max_ssh_sessions=>9,
     :connection_timeout=>15,
     :connection_retries=>5,
     :connection_retry_sleep=>1,
     :max_wait_until_ready=>600,
     :ssh_gateway=>nil,
     :ssh_gateway_username=>nil,
     :ssh_key=>nil,
     :compression=>false,
     :compression_level=>
      #<Proc:0x48fc8e8@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/transport/ssh.rb:64>},
   @connection=nil,
   @instance=#<Kitchen::Instance:0x48b5350 ...>>,
 @verifier=
  #<Kitchen::Verifier::Busser:0x48b5a40
   @config=
    {:name=>"busser",
     :kitchen_root=>"C:/Users/Sean/Documents/projects/kitchen-lxd_nexus",
     :test_base_path=>
      "C:/Users/Sean/Documents/projects/kitchen-lxd_nexus/test/integration",
     :log_level=>:info,
     :http_proxy=>nil,
     :https_proxy=>nil,
     :ftp_proxy=>nil,
     :root_path=>
      #<Proc:0x3cd7be0@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/verifier/base.rb:36>,
     :sudo=>
      #<Proc:0x3cd7b80@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/verifier/base.rb:40>,
     :chef_omnibus_root=>"/opt/chef",
     :sudo_command=>
      #<Proc:0x3cd7b50@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/verifier/base.rb:46>,
     :command_prefix=>nil,
     :suite_name=>
      #<Proc:0x3cd7af0@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/verifier/base.rb:52>,
     :busser_bin=>
      #<Proc:0x48b6190@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/verifier/busser.rb:36>,
     :ruby_bindir=>
      #<Proc:0x48b6118@C:/opscode/chefdk/embedded/lib/ruby/gems/2.4.0/gems/test-kitchen-1.17.0/lib/kitchen/verifier/busser.rb:42>,
     :version=>"busser"},
   @instance=#<Kitchen::Instance:0x48b5350 ...>>>
"State (create):"
{}
=end
