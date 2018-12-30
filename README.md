# kitchen-lxd_sling [![Build Status](https://travis-ci.org/NexusSW/kitchen-lxd_sling.svg?branch=master)](https://travis-ci.org/NexusSW/kitchen-lxd_sling) [![Dependency Status](https://gemnasium.com/badges/github.com/NexusSW/kitchen-lxd_sling.svg)](https://gemnasium.com/github.com/NexusSW/kitchen-lxd_sling)

Test Kitchen driver for LXD.  This gem provides a driver, and a transport allowing native access to your containers running under LXD.

## Requirements

* [test-kitchen](https://github.com/test-kitchen/test-kitchen/)
* LXD host running version >= 2.0
* Authority to access your LXD host:
  * be a member of the lxd group if accessing LXD locally
  * or have an already trusted client cert if accessing remotely

## Installation

    $ gem install kitchen-lxd_sling

And if you're testing with inspec, you'll also need to install our Train transport:  (Requires `kitchen-inspec ~> 0.22`)

    $ gem install train-lxd

## Usage

Basic kitchen.yml entries with a local LXD host:

```yaml
driver: lxd
transport: lxd
...
```

And if your host is remote to where you're running kitchen, then this is 'likely' all that you will need:

```yaml
driver:
  name: lxd
  server: <hostname>
  rest_options:
    verify_ssl: false

transport: lxd
...
```

### Available options

```yaml
driver:
  name: lxd
  server: <hostname>
  port: 8443
  username: ubuntu
  image_server:
    server: https://images.linuxcontainers.org
    protocol: simplestreams
  alias: ubuntu/xenial
  fingerprint: ce8d746a8567
  properties:
    architecture: amd64
    os: Ubuntu
    release: xenial
  profiles:
    - default
    - kitchen
    ...
  config:
    security.privileged: true
    security.nesting: true
    linux.kernel_modules: ip_tables,ip6_tables
    ...
  devices:
    vda:
      type: unix-block
      source: /dev/storage/ceph-01
      path: /dev/vda
  ssh_login:
    username: ubuntu
    public_key: <local path to file: ~/.ssh/id_rsa.pub>
  rest_options:
    verify_ssl: false
    ssl:
      verify: false
      client_cert: <local path to file: ~/.config/lxc/client.crt>
      client_key: <local path to file: ~/.config/lxc/client.key>
...
```

#### Options (explained)

option | default | description
|---|:---:|---|
server | | Hostname of a remote LXD server.  If left unspecified, then local CLI commands will be issued via `lxc`.
port | 8443 | Port on **server** where LXD is listening.  Ignored unless **server** is specified.
username | root | If the base image has additional user accounts built-in, then change this value to run all commands as a different user.  **Warning**: _passwordless sudo may be required by the remainder of the test suite_
image_server.server | https://images.linuxcontainers.org | Default source for base container images
image_server.protocol | _\<calculated>_ | `simplestreams` or `lxd` protocol with which to communicate with the **image_server**
alias | _\<calculated>_ | Name of the image on the **image_server**.  Derived from platform name in kitchen.yml's `platforms:` section unless specified here, and unless **fingerprint** or **properties** are specified.
fingerprint | | Fingerprint of a specific image on the **image_server**
properties | | Search parameters for finding an image on the **image_server**
profiles | default | Profiles on the LXD host to apply to any newly created containers
config | | Additional container properties passed verbatim to the LXD Host.  Refer to LXD's documentation for valid values https://github.com/lxc/lxd/blob/master/doc/containers.md
ssh_login.username | | If the base image has sshd enabled and running, specify the username here and the driver will set up the container for ssh access.  Overrides the base **username**
ssh_login.public_key | ~/.ssh/id_rsa.pub | Public key to use for authenticating ssh connections.
rest_options.verify_ssl | true | _Convenience option_ When connecting to a remote LXD host, should the hosts SSL certificate be verified
rest_options.ssl.verify | true | Overrides **rest_options.verify_ssl**.
rest_options.ssl.client_cert | ~/.config/lxc/client.crt | Client certificate authenticating access to the LXD host.
rest_options.ssl.client_key | ~/.config/lxc/client.key | Private key for the client certificate.