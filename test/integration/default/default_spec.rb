
# Verify that chef client is installed in the container
#   indirectly tests that the container is running, sane, and has net
#   and exercises the kitchen-inspec patch

describe 'container' do
  expect(File.exist?('/opt/chef')).to be true
end
