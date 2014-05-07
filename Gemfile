source :rubygems

gem "chef", "~> 11.12.2"
gem "ffi-rzmq"

gemspec

# For some unknown reason we seem to not pick this up from our dependencies
gem "rest-client", :git => "git://github.com/opscode/rest-client.git"

# Even though chef-pedant is a dependency of oc-chef-pedant, the gem
# is not on RubyGems, so we have to lock the dependency here, too.  It
# should be whatever the specified version of oc-chef-pedant depends
# on.
gem 'chef-pedant', :path => '/srv/piab/mounts/chef-pedant'
gem 'oc-chef-pedant', :path => '/srv/piab/mounts/oc-chef-pedant'
gem 'opscode-pushy-client', :path => '/srv/piab/mounts/opscode-pushy-client'
