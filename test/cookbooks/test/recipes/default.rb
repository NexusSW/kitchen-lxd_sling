
lxd "default" do
  network_address "[::]"
  auto_install true
  branch :lts
  users "travis" if ENV["TRAVIS"] == "true"
end

lxd_network "lxdbr0"
lxd_profile "default"

lxd_device "eth0" do
  location :profile
  location_name "default"
  type :nic
  parent "lxdbr0"
  nictype :bridged
end

if ENV["TRAVIS"] == "true"
  directory "/home/travis/.config/lxc" do
    action :delete
    recursive true
  end
end
