# kitchen-lxd_sling [![Build Status](https://travis-ci.org/NexusSW/kitchen-lxd_sling.svg?branch=master)](https://travis-ci.org/NexusSW/kitchen-lxd_sling) [![Dependency Status](https://gemnasium.com/badges/github.com/NexusSW/kitchen-lxd_sling.svg)](https://gemnasium.com/github.com/NexusSW/kitchen-lxd_sling)

Test Kitchen driver for LXD.  This gem provides a driver, and a transport allowing native access to your containers running under LXD.

## Requirements

* [test-kitchen](https://github.com/test-kitchen/test-kitchen/)
* LXD host running version >= 2.0

## Installation

    $ gem install kitchen-lxd_sling

And if you're testing with inspec, you'll also need to install a Train transport:  (Requires kitchen-inspec ~> 0.22)

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

All options:

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
  config:
    security.privileged: true
    security.nesting: true
    ...
  ssh_login:
    username: ubuntu
    public_key: <local path to file>
  rest_options:
    verify_ssl: false
    ssl:
      verify: false
      client_cert: <local path to file>
      client_key: <local path to file>
...
```
