include_recipe 'hurry-up-and-test::set_non_nat_vbox_ip'

Chef::Log.warn("Node fqdn: #{node['fqdn']}")
Chef::Log.warn("Node ipaddress: #{node['ipaddress']}")

search(:node, 'fqdn:client-*') do |n|
  hostsfile_entry n['ipaddress'] do
    hostname n['fqdn']
    action :create
  end
end

chef_ingredient 'chef-server' do
  channel :stable
  action [:install, :reconfigure]
end

chef_ingredient 'manage' do
  channel :stable
  accept_license true
  action [:install, :reconfigure]
end

chef_ingredient 'push-jobs-server' do
  channel :stable
  accept_license true
  action [:install, :reconfigure]
end

execute 'create admin' do
  command <<-EOF.gsub(/\s+/, ' ').strip!
    chef-server-ctl user-create
      admin
      Adam Admin
      cheffio@chef.io
      none11
      --filename #{File.join('/srv', 'admin.pem')}
  EOF
  not_if 'chef-server-ctl user-show admin'
  notifies :run, 'execute[create org]', :immediately
end

execute 'create org' do
  command <<-EOF.gsub(/\s+/, ' ').strip!
    chef-server-ctl org-create
    admin-org
    'Delightful Development Organization'
    --association_user admin
    --filename #{File.join('/srv', 'admin-validator.pem')}
  EOF
  action :nothing
