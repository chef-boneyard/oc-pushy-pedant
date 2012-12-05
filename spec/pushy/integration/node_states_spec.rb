#
# -*- indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
# ex: ts=4 sw=4 et
#
# Author:: Douglas Triggs (<doug@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
#

require 'pedant/rspec/common'

describe "Node_States API Endpoint", :focus, :node_states do
  let(:node_name) { 'some_node' }
  let(:non_existent_node_name) { 'not_a_number' }

  let(:failed_to_authenticate_as_invalid_msg) {
    ["Failed to authenticate as 'invalid'. Ensure that your node_name and client key are correct."] }
  let(:outside_user_not_associated_msg) {
    ["'pedant-nobody' not associated with organization '#{org}'"] }
  let(:cannot_load_nonexistent_msg) { 
    ["Cannot load client #{non_existent_node_name}"] }
  let(:payload) {
    {
      "availability" => "unavailable",
      "node_name" => node_name,
      "status" => "offline"
    } }

  describe 'access control with no pushy_job_readers' do
    context 'GET /node_states' do
      it 'returns a 200 ("OK") for admin' do
        get(api_url("/pushy/node_states/"), admin_user) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 200 ("OK") for normal user' do
        get(api_url("/pushy/node_states/"), normal_user) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 200 ("OK") for admin client' do
        get(api_url("/pushy/node_states/"), platform.admin_client) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 200 ("OK") for non-admin client', :pending do
        get(api_url("/pushy/node_states/"), platform.non_admin_client) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 401 ("Unauthorized") for invalid user' do
        get(api_url("/pushy/node_states"),
            invalid_user) do |response|
          response.
            should look_like({
                               :status => 401,
                               :body_exact => {
                                 "error" => failed_to_authenticate_as_invalid_msg
                               }
                             })
        end
      end

      it 'returns a 403 ("Forbidden") for outside user', :pending do
        get(api_url("/pushy/node_states"),
            outside_user) do |response|
          response.should look_like({
                                      :status => 403,
                                      :body_exact => {
                                        "error" => outside_user_not_associated_msg
                                      }
                                    })
        end
      end
    end # context 'GET /node_states'

    context 'GET /node_states/<name>' do
      it 'returns a 200 ("OK") for admin' do
        get(api_url("/pushy/node_states/#{node_name}"), admin_user) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body_exact => payload
                                    })
        end
      end

      it 'returns a 200 ("OK") for normal user' do
        get(api_url("/pushy/node_states/#{node_name}"), normal_user) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body_exact => payload
                                    })
        end
      end

      it 'returns a 200 ("OK") for non-admin client', :pending do
        get(api_url("/pushy/node_states/#{node_name}"),
            platform.non_admin_client) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body_exact => payload
                                    })
        end
      end

      it 'returns a 200 ("OK") for admin client' do
        get(api_url("/pushy/node_states/#{node_name}"),
            platform.admin_client) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body_exact => payload
                                    })
        end
      end

      it 'returns a 401 ("Unauthorized") for invalid user' do
        get(api_url("/pushy/node_states/#{node_name}"),
            invalid_user) do |response|
          response.should look_like({
                                      :status => 401,
                                      :body_exact => {
                                        "error" => failed_to_authenticate_as_invalid_msg
                                      }
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for outside user', :pending do
        get(api_url("/pushy/node_states/#{node_name}"),
            outside_user) do |response|
          response.should look_like({
                                      :status => 403,
                                      :body_exact => {
                                        "error" => outside_user_not_associated_msg
                                      }
                                    })
        end
      end

      it 'returns a 404 ("Not Found") for missing node_state for admin', :pending do
        get(api_url("/pushy/node_states/#{non_existent_node_name}"),
            admin_user) do |response|
          response.should look_like({
                                      :status => 404,
                                      :body_exact => {
                                        "error" => cannot_load_nonexistent_msg
                                      }
                                    })
        end
      end

      it 'returns a 404 ("Not Found") for missing node_state for normal user', :pending do

        get(api_url("/pushy/node_states/#{non_existent_node_name}"),
            normal_user) do |response|
          response.should look_like({
                                      :status => 404,
                                      :body_exact => {
                                        "error" => cannot_load_nonexistent_msg
                                      }
                                    })
        end
      end
    end # context 'GET /node_states/<name>'
  end # describe 'access control with no pushy_job_readers'

  describe 'access control with pushy_job_readers' do
    # Doing these in reverse for extra fun; this will guarantee it doesn't
    # "accidentally" work if the groups are missing
    let(:member) { normal_user }
    let(:non_member) { admin_user }
    let(:member_client) { platform.non_admin_client }
    let(:non_member_client) { platform.admin_client }

    let(:readers) { "pushy_job_readers" }
    let(:readers_group) { {"groupname" => readers} }

    before(:all) do
      post(api_url("/groups/"), admin_user, :payload => readers_group)

      # TODO: this is going to fail until we add users to the groups
    end

    after(:all) do
      delete(api_url("/groups/#{readers}"), admin_user)
    end

    context 'GET /node_states' do
      it 'returns a 200 ("OK") for member' do
        get(api_url("/pushy/node_states/"), member) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for non-member' do
        get(api_url("/pushy/node_states/"), non_member) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end

      it 'returns a 200 ("OK") for member client' do
        get(api_url("/pushy/node_states/"), member_client) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for non-member client' do
        get(api_url("/pushy/node_states/"), non_member_client) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end
    end # context 'GET /node_states'

    context 'GET /node_states/<name>' do
      it 'returns a 200 ("OK") for member' do
        get(api_url("/pushy/node_states/#{node_name}"), member) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body_exact => payload
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for non-member' do
        get(api_url("/pushy/node_states/#{node_name}"), non_member) do |response|
          response.should look_like({
                                      :status => 403,
                                      :body_exact => payload
                                    })
        end
      end

      it 'returns a 200 ("OK") for member client' do
        get(api_url("/pushy/node_states/#{node_name}"),
            member_client) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body_exact => payload
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for non-member client' do
        get(api_url("/pushy/node_states/#{node_name}"),
            non_member_client) do |response|
          response.should look_like({
                                      :status => 403,
                                      :body_exact => payload
                                    })
        end
      end
    end # context 'GET /node_states/<name>'
  end # describe 'access control with pushy_job_readers'
end