
# Verify that chef client is installed in the container
#   indirectly tests that the container is running, sane, and has net
#   and exercises the kitchen-inspec patch

describe directory"/opt/chef" do
  it { should exist }
end
