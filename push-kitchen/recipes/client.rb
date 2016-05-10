include_recipe 'hurry-up-and-test::set_non_nat_vbox_ip'

Chef::Log.warn("Node fqdn: #{node['fqdn']}")
Chef::Log.warn("Node ipaddress: #{node['ipaddress']}")

search(:node, 'fqdn:server-*') do |n|
  hostsfile_entry n['ipaddress'] do
    hostname n['fqdn']
    action :create
  end
end

chef_ingredient 'chef' do
  channel :stable
  action [:install, :reconfigure]
end

# chef_ingredient 'push-jobs-client' do
#   channel :stable
#   accept_license true
#   action [:install, :reconfigure]
# end

include_recipe 'push-jobs'
