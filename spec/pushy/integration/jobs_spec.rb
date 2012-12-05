#
# -*- indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
# ex: ts=4 sw=4 et
#
# Author:: Douglas Triggs (<doug@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
#

require 'pedant/rspec/common'

describe "Jobs API Endpoint", :jobs do
  # TODO: un-hard-code this:
  let(:node_name) { 'DONKEY' }
  let(:nodes) { %w{DONKEY} }

  let(:payload) {
    {
      'command' => 'sleep 2',
      'nodes' => nodes
    }
  }

  let(:job_name) {
    # This is evaluated at runtime, so there's always a (short-lived) job to
    # detect during the test

    post(api_url("/pushy/jobs"), admin_user, :payload => payload)
    get(api_url("/pushy/jobs"), admin_user) do |response|
      list = JSON.parse(response.body)
      list[0]["id"]
    end
  }

  let(:non_existent_job) { 'not_a_number' }
  let(:failed_to_authenticate_as_invalid_msg) {
    ["Failed to authenticate as 'invalid'. Ensure that your node_name and client key are correct."] }
  let(:outside_user_not_associated_msg) {
    ["'pedant-nobody' not associated with organization '#{org}'"] }

  describe 'access control with no pushy_job groups' do
    context 'GET /jobs' do
      it 'returns a 200 ("OK") for admin' do
        get(api_url("/pushy/jobs/"), admin_user) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 200 ("OK") for normal user' do
        get(api_url("/pushy/jobs/"), normal_user) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 200 ("OK") for admin client' do
        get(api_url("/pushy/jobs/"), platform.admin_client) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 200 ("OK") for non-admin client', :pending do
        get(api_url("/pushy/jobs/"), platform.non_admin_client) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 401 ("Unauthorized") for invalid user' do
        get(api_url("/pushy/jobs"),
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
        get(api_url("/pushy/jobs"),
            outside_user) do |response|
          response.should look_like({
                                      :status => 403,
                                      :body_exact => {
                                        "error" => outside_user_not_associated_msg
                                      }
                                    })
        end
      end
    end # context 'GET /jobs'

    context 'POST /jobs' do
      it 'returns a 200 ("OK") for admin' do
        post(api_url("/pushy/jobs/"), admin_user, :payload => payload) do |response|
          response.should look_like({
                                      :status => 201
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for normal user' do
        post(api_url("/pushy/jobs/"), normal_user, :payload => payload) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end

      it 'returns a 200 ("OK") for admin client' do
        post(api_url("/pushy/jobs/"), platform.admin_client,
             :payload => payload) do |response|
          response.should look_like({
                                      :status => 201
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for non-admin client', :pending do
        post(api_url("/pushy/jobs/"), platform.non_admin_client,
             :payload => payload) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end

      it 'returns a 401 ("Unauthorized") for invalid user' do
        post(api_url("/pushy/jobs"), invalid_user, :payload => payload) do |response|
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
        post(api_url("/pushy/jobs"), outside_user, :payload => payload) do |response|
          response.should look_like({
                                      :status => 403,
                                      :body_exact => {
                                        "error" => outside_user_not_associated_msg
                                      }
                                    })
        end
      end
    end # context 'POST /jobs'

    context 'GET /jobs/<name>' do
      it 'returns a 200 ("OK") for admin' do
        get(api_url("/pushy/jobs/#{job_name}"), admin_user) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 200 ("OK") for normal user' do
        get(api_url("/pushy/jobs/#{job_name}"), normal_user) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 200 ("OK") for admin client' do
        get(api_url("/pushy/jobs/#{job_name}"), platform.admin_client) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 200 ("OK") for non-admin client', :pending do
        get(api_url("/pushy/jobs/#{job_name}"), platform.non_admin_client) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 401 ("Unauthorized") for invalid user' do
        get(api_url("/pushy/jobs/#{job_name}"),
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
        get(api_url("/pushy/jobs/#{job_name}"),
            outside_user) do |response|
          response.should look_like({
                                      :status => 403,
                                      :body_exact => {
                                        "error" => outside_user_not_associated_msg
                                      }
                                    })
        end
      end

      it 'returns a 404 ("Not Found") for missing node_state for admin' do
        get(api_url("/pushy/jobs/#{non_existent_job}"),
            admin_user) do |response|
          response.should look_like({
                                      :status => 404
                                    })
        end
      end

      it 'returns a 404 ("Not Found") for missing node_state for normal user' do
        get(api_url("/pushy/jobs/#{non_existent_job}"),
            normal_user) do |response|
          response.should look_like({
                                      :status => 404
                                    })
        end
      end
    end # context 'GET /jobs/<name>'
  end # describe 'access control with no pushy_job groups'

  describe 'access control with pushy_job groups' do
    # Doing these in reverse for extra fun; this will guarantee it doesn't
    # "accidentally" work if the groups are missing
    let(:member) { normal_user }
    let(:non_member) { admin_user }
    let(:member_client) { platform.non_admin_client }
    let(:non_member_client) { platform.admin_client }

    let(:readers) { "pushy_job_readers" }
    let(:writers) { "pushy_job_writers" }
    let(:readers_group) { {"groupname" => readers} }
    let(:writers_group) { {"groupname" => writers} }

    before(:all) do
      post(api_url("/groups/"), admin_user, :payload => readers_group)
      post(api_url("/groups/"), admin_user, :payload => writers_group)

      # TODO: this is going to fail until we add users to the groups
    end

    after(:all) do
      delete(api_url("/groups/#{readers}"), admin_user)
      delete(api_url("/groups/#{writers}"), admin_user)
    end
      
    context 'GET /jobs with pushy_job_readers' do
      it 'returns a 200 ("OK") for member' do
        get(api_url("/pushy/jobs/"), member) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for non-member' do
        get(api_url("/pushy/jobs/"), non_member) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end

      it 'returns a 200 ("OK") for member client' do
        get(api_url("/pushy/jobs/"), member_client) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for non-member client' do
        get(api_url("/pushy/jobs/"), non_member_client) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end
    end # context 'GET /jobs with pushy_job_readers'

    context 'POST /jobs with pushy_job_writers' do
      it 'returns a 200 ("OK") for member' do
        post(api_url("/pushy/jobs/"), member, :payload => payload) do |response|
          response.should look_like({
                                      :status => 201
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for non-member' do
        post(api_url("/pushy/jobs/"), non_member, :payload => payload) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end

      it 'returns a 200 ("OK") for member client' do
        post(api_url("/pushy/jobs/"), member_client,
             :payload => payload) do |response|
          response.should look_like({
                                      :status => 201
                                    })
        end
      end

      it 'returns a 403 ("Forbidden") for non-member client' do
        post(api_url("/pushy/jobs/"), non_member_client,
             :payload => payload) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end
    end # context 'POST /jobs with pushy_job_writers'

    context 'GET /jobs/<name> with pushy_job_readers' do
      it 'returns a 200 ("OK") for member' do
        get(api_url("/pushy/jobs/#{job_name}"), member) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 403 ("OK") for non-member' do
        get(api_url("/pushy/jobs/#{job_name}"), non_member) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end

      it 'returns a 200 ("OK") for member client' do
        get(api_url("/pushy/jobs/#{job_name}"), member_client) do |response|
          response.should look_like({
                                      :status => 200
                                    })
        end
      end

      it 'returns a 403 ("OK") for non-member client' do
        get(api_url("/pushy/jobs/#{job_name}"), non_member_client) do |response|
          response.should look_like({
                                      :status => 403
                                    })
        end
      end
    end # context 'GET /jobs/<name> with pushy_job_readers'
  end # describe 'access control with pushy_job groups'
end # describe "Jobs API Endpoint"