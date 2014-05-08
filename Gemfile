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
gem 'chef-pedant', :git => "git@github.com:opscode/chef-pedant.git", :tag => '1.0.28'
gem 'oc-chef-pedant', :git => "git@github.com:opscode/oc-chef-pedant.git", :tag => '1.0.28'
gem 'opscode-pushy-client', :git => "git@github.com:opscode/opscode-pushy-client.git", :tag => '1.0.1'
