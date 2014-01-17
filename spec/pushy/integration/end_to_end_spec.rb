
# -*- indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
#
# Author:: John Keiser (<jkeiser@opscode.com>)
# Author:: Douglas Triggs (<doug@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
#

require 'pushy/spec_helper'
require 'fileutils'

describe "end-to-end-test" do
  include_context "end_to_end_util"

  let(:status_url) { api_url("/_status").gsub(/organizations\/[^\/]*.\//, '/pushy') }

  before :all do
    if (Pedant::Config.pushy_client_debug)
      Chef::Log.level = :debug
    end
  end

  after :each do
    if @clients
      @clients.each do |client_name, client|
        stop_client(client_name) if @clients[client_name][:client]
      end
      @clients = nil
    end
  end

  context 'with one client' do
    before :each do
      start_new_clients('DONKEY')
    end

    it 'node count should be 1' do
      get(status_url, admin_user) do |response|
        response.should look_like({
          :node_fsm_count => 1
        })
      end
    end

    context 'that is already running chef-client' do
      before :each do
        # create a lockfile to simulate a chef-client run
        lockfile_location = Chef::Config[:lockfile] || "#{Chef::Config[:file_cache_path]}/chef-client-running.pid"
        # Ensure the directory for the lockfile exists
        FileUtils.mkdir_p(File.expand_path('..', lockfile_location))
        @lockfile = File.open(lockfile_location, File::RDWR|File::CREAT, 0644)
        @lockfile.flock(File::LOCK_EX|File::LOCK_NB)
      end

      after :each do
        # release the lock
        @lockfile.flock(File::LOCK_UN)
        @lockfile.close
      end

      it 'should nack when asked to commit to another job' do
        job = start_job('chef-client', %w{DONKEY})
        get_job(job['uri']).should == {
          'command' => 'chef-client',
          'run_timeout' => 3600,
          'nodes' => { 'nacked' => [ 'DONKEY' ] },
          'status' => 'quorum_failed'
        }
      end

    end

    context 'when running a job' do
      before(:each) do
        node = get_node_state("DONKEY")
        start_echo_job_on_all_clients
      end

      it 'is marked complete' do
        echo_job_should_complete_on_all_clients
      end
    end

    context 'when running a job and a client goes down and quickly back up' do
      before :each do
        @job = start_job('sleep 1', %w{DONKEY})
        wait_for_job_status(@job['uri'], 'running')
        stop_client('DONKEY')
        start_client('DONKEY')
      end

      it 'should be marked as unavailable immediatly' do
        get_job(@job['uri']).should == {
          'command' => 'sleep 1',
          'run_timeout' => 3600,
          'nodes' => { 'crashed' => [ 'DONKEY' ] },
          'status' => 'complete'
        }
      end
    end

    context 'when running a failing job' do
      let(:command) {'ruby -e "exit 1"'}
      before(:each) do
        @job1 = start_job(command, %w{DONKEY})
      end

      it 'should be marked as failed' do
        wait_for_job_complete(@job1['uri'])
        get_job(@job1['uri']).should == {
          'command' => command,
          'run_timeout' => 3600,
          'nodes' => { 'failed' => [ 'DONKEY' ] },
          'status' => 'complete'
        }
      end
    end

    context 'when client shuts down' do
      before(:each) do
        stop_client('DONKEY')
        wait_for_node_status('offline', 'DONKEY')
      end

      it 'node count should be 0' do
        get(status_url, admin_user) do |response|
          response.should look_like({
            :node_fsm_count => 0
          })
        end
      end
    end

    context 'when running a long running job' do
      before :each do
        start_and_wait_for_job('sleep 10', [ 'DONKEY' ])
      end

      context 'when the client sends an unexpected message with a valid job_id' do
        before :each do
          client = @clients['DONKEY'][:client]
          job_id = @response["uri"].split("/").last
          client.send_command(:nack_commit, job_id)
        end

        it 'aborts the node and we can run another job on the node afterwards successfully' do
          job = wait_for_job_complete(@response["uri"])
          job['nodes'].should == { 'crashed' => [ 'DONKEY' ] }

          wait_for_node_to_come_out_of_rehab('DONKEY')

          start_echo_job_on_all_clients
          echo_job_should_complete_on_all_clients
        end
      end

      context 'when the client sends an unexpected message with a bad timestamp' do
        before :each do
          client = @clients['DONKEY'][:client]
          job_id = @response["uri"].split("/").last

          @expired_time = Time.now - (1000)
          PushyClient::ProtocolHandler::TimeSendWrapper.stub!(:now).and_return(@expired_time, Time.now())

          client.send_command(:nack_commit, job_id)
        end

        it 'the message is ignored and the job completes successfully' do
          job = wait_for_job_complete(@response["uri"])
          job['nodes'].should == { 'succeeded' => [ 'DONKEY' ] }
        end
      end

      context 'when the client sends an unexpected message with a old, but good timestamp' do
        before :each do
          client = @clients['DONKEY'][:client]
          job_id = @response["uri"].split("/").last

          @expired_time = Time.now - (100) # assumes timeout is 500 s.
          PushyClient::ProtocolHandler::TimeSendWrapper.stub!(:now).and_return(@expired_time, Time.now())

          client.send_command(:nack_commit, job_id)
        end

        it 'aborts the node and we can run another job on the node afterwards successfully' do
          job = wait_for_job_complete(@response["uri"])
          job['nodes'].should == { 'crashed' => [ 'DONKEY' ] }

          wait_for_node_to_come_out_of_rehab('DONKEY')

          start_echo_job_on_all_clients
          echo_job_should_complete_on_all_clients
        end
      end


      context 'when the client sends an unexpected message with an invalid job_id' do
        before :each do
          client = @clients['DONKEY'][:client]
          client.send_command(:nack_commit, 'a')
        end

        it 'aborts the node and we can run another job on the node afterwards successfully' do
          job = wait_for_job_complete(@response["uri"])
          job['nodes'].should == { 'crashed' => [ 'DONKEY' ] }

          wait_for_node_to_come_out_of_rehab('DONKEY')

          start_echo_job_on_all_clients
          echo_job_should_complete_on_all_clients
        end
      end

    end

    context 'which sends aborted with a nonexistent job id' do
      before(:each) do
        @clients['DONKEY'][:client].should_not_receive(:abort)
        @clients['DONKEY'][:client].send_command(:aborted, 'a')
      end

      it 'does not go into rehab (receives no abort)' do
        sleep(1)
      end
    end

    context 'when running a job that completes before its timeout' do
      before(:each) do
        File.delete('/tmp/pushytest') if File.exist?('/tmp/pushytest')
        start_and_wait_for_job(echo_yahoo, [ 'DONKEY' ], :run_timeout => 2)
      end

      it 'completes' do
        job = wait_for_job_complete(@response['uri'])
        job.should == {
          'command' => echo_yahoo,
          'run_timeout' => 2,
          'nodes' => { 'succeeded' => [ 'DONKEY' ] },
          'status' => 'complete'
        }
        IO.read('/tmp/pushytest').should == "YAHOO\n"*@clients.length
      end
    end

    context 'when running a job that lasts longer than its timeout' do
      before(:each) do
        File.delete('/tmp/pushytest') if File.exist?('/tmp/pushytest')
        start_and_wait_for_job('sleep 2', [ 'DONKEY' ], :run_timeout => 1)
      end

      it 'times out and aborts' do
        job = wait_for_job_status(@response['uri'], 'timed_out')
        job.should == {
          'command' => 'sleep 2',
          'run_timeout' => 1,
          'nodes' => { 'timed_out' => [ 'DONKEY' ] },
          'status' => 'timed_out'
        }
        sleep(1.2)
        File.exist?('/tmp/pushytest').should be_false
      end
    end

    context 'that forgets to send the ack_commit message', :slow do
      before :each do
        override_send_command('DONKEY') do |real_send_command, message, job_id|
          real_send_command.call(message, job_id) unless message == :ack_commit
        end
      end

      it 'job times out and fails to start' do
        response = start_job(echo_yahoo, ['DONKEY'])
        get(api_url("pushy/node_states/DONKEY"), admin_user) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body => {
                                        'status' => 'online'
                                      }})
        end
        # While we're waiting, let's verify that the node shows as "new".  This
        # is the only test where we're guaranteed to get this response--most
        # tests will vote immediately.
        get(response['uri'], admin_user) do |response|
          response.should look_like({
            :status => 200,
            :body => {
              'nodes' => { 'new' => ['DONKEY'] }
            }
          })
        end
        job = wait_for_job_status(response['uri'], 'quorum_failed', :timeout => 65)
        job['nodes'].should == { 'unavailable' => [ 'DONKEY' ] }
        # This verifies our assumption that this was caused by the TIMEOUT rather
        # than the node being detected as down
        get(api_url("pushy/node_states/DONKEY"), admin_user) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body => {
                                        'status' => 'online'
                                      }})
        end
      end
    end

    context 'that dies before running a job' do
      before :each do
        stop_client('DONKEY')
        wait_for_node_status('offline', 'DONKEY')
      end

      it 'job immediately fails to start' do
        response = start_job(echo_yahoo, ['DONKEY'])

        # TODO check immediacy!  This could erroneously succeed on timing out.
        job = wait_for_job_status(response['uri'], 'quorum_failed')
        job['nodes'].should == { 'unavailable' => [ 'DONKEY' ] }
      end
    end

    context 'that dies just before running the job, but has not yet been detected as down' do
      before :each do
        stop_client('DONKEY')
      end

      it 'job fails to start when down is detected' do
        response = start_job(echo_yahoo, ['DONKEY'])
        get(api_url("pushy/node_states/DONKEY"), admin_user) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body => {
                                        'status' => 'online'
                                      }})
        end
        # TODO we should ensure that this happened due to down detection, not
        # timeout.  Fine for now, because there is no timeout :)
        job = wait_for_job_status(response['uri'], 'quorum_failed')
        job['nodes'].should == { 'unavailable' => [ 'DONKEY' ] }
      end
    end

    context 'when the client crashes after reporting "ready" but before running the command' do
      before :each do
        override_send_command('DONKEY') do |real_send_command, message, job_id|
          real_send_command.call(message, job_id)
          if message == :ack_commit
            kill_client('DONKEY')
          end
        end
      end

      it 'job marks node as crashed when down is detected' do
        response = start_job(echo_yahoo, ['DONKEY'])
        get(api_url("pushy/node_states/DONKEY"), admin_user) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body => {
                                        'status' => 'online'
                                      }})
        end
        # TODO we should ensure that this happened due to down detection, not
        # timeout.  Fine for now, because there is no timeout :)
        job = wait_for_job_status(response['uri'], 'complete')
        job['nodes'].should == { 'crashed' => [ 'DONKEY' ] }
      end
    end

    context 'when the client crashes after running but before completing the command' do
      before :each do
        # Set it up so the client will crash as soon as it changes to "voting"
        client = @clients['DONKEY'][:client]
        client.on_job_state_change { |state| kill_client('DONKEY') if state[:state] == :running }
      end

      it 'job marks node as crashed when down is detected' do
        response = start_job(echo_yahoo, ['DONKEY'])
        get(api_url("pushy/node_states/DONKEY"), admin_user) do |response|
          response.should look_like({
                                      :status => 200,
                                      :body => {
                                        'status' => 'online'
                                      }})
        end
        # TODO we should ensure that this happened due to down detection, not
        # timeout.  Fine for now, because there is no timeout :)
        job = wait_for_job_status(response['uri'], 'complete')
        job['nodes'].should == { 'crashed' => [ 'DONKEY' ] }
      end
    end

    context 'whitelist tests' do
      it 'trying to run a command that is not on the whitelist fails' do
        job = start_job('echo nevereverever', ['DONKEY'])
        job = wait_for_job_status(job['uri'], 'quorum_failed')
        job.should == {
          'command' => 'echo nevereverever',
          'run_timeout' => 3600,
          'nodes' => {
            'nacked' => [ 'DONKEY' ]
          },
          'status' => 'quorum_failed'
        }
      end

      it 'running a command with a shortened whitelist name that should succeed, it succeeds' do
        job = start_job('this_oughta_succeed', ['DONKEY'])
        job = wait_for_job_status(job['uri'], 'complete')
        job.should == {
          'command' => 'this_oughta_succeed',
          'run_timeout' => 3600,
          'nodes' => {
            'succeeded' => [ 'DONKEY' ]
          },
          'status' => 'complete'
        }
      end

      it 'running a command with a shortened whitelist name that should fail, it fails' do
        job = start_job('this_oughta_fail', ['DONKEY'])
        job = wait_for_job_status(job['uri'], 'complete')
        job.should == {
          'command' => 'this_oughta_fail',
          'run_timeout' => 3600,
          'nodes' => {
            'failed' => [ 'DONKEY' ]
          },
          'status' => 'complete'
        }
      end
    end
  end

  context 'with a client that is killed and comes back up quickly' do
    before :each do
      start_new_clients('DONKEY')
      kill_client('DONKEY')
      start_client('DONKEY')
    end

    context 'when running a job' do
      before(:each) do
        start_echo_job_on_all_clients
      end

      it 'is marked complete' do
        echo_job_should_complete_on_all_clients
      end
    end
  end

  context 'with a dead client that comes back down after a while' do
    before :each do
      start_new_clients('DONKEY')
      kill_client('DONKEY')
      wait_for_node_status('offline', 'DONKEY')
      # Start that sucker back up
      start_client('DONKEY')
    end

    context 'when running a job' do
      before(:each) do
        start_echo_job_on_all_clients
      end

      it 'is marked complete' do
        echo_job_should_complete_on_all_clients
      end
    end
  end

  context 'with a client that goes down and back up quickly' do
    before :each do
      start_new_clients('DONKEY')
      stop_client('DONKEY')
      start_client('DONKEY')
    end

    context 'when running a job' do
      before(:each) do
        start_echo_job_on_all_clients
      end

      it 'is marked complete' do
        echo_job_should_complete_on_all_clients
      end
    end
  end

  context 'with a client that goes down and back up a while later' do
    before :each do
      start_new_clients('DONKEY')
      stop_client('DONKEY')
      wait_for_node_status('offline', 'DONKEY')
      start_client('DONKEY')
    end

    context 'when running a job' do
      before(:each) do
        start_echo_job_on_all_clients
      end

      it 'is marked complete' do
        echo_job_should_complete_on_all_clients
      end
    end
  end

  context 'with three clients' do
    before :each do
      start_new_clients('DONKEY', 'FARQUAD', 'FIONA')
    end

    it 'node count should be 3' do
      get(status_url, admin_user) do |response|
        response.should look_like({
          :node_fsm_count => 3
        })
      end
    end

    context 'when a client shuts down' do
      before(:each) do
        stop_client('DONKEY')
        wait_for_node_status('offline', 'DONKEY')
      end

      it 'node count should be 2' do
        get(status_url, admin_user) do |response|
          response.should look_like({
            :node_fsm_count => 2
          })
        end
      end
    end

    context 'when all clients shut down' do
      before(:each) do
        stop_client('DONKEY')
        stop_client('FARQUAD')
        stop_client('FIONA')
        wait_for_node_status('offline', 'DONKEY', 'FARQUAD', 'FIONA')
      end

      it 'node count should be 0' do
        get(status_url, admin_user) do |response|
          response.should look_like({
            :node_fsm_count => 0
          })
        end
      end
    end

    context 'when running a job' do
      before(:each) do
        start_echo_job_on_all_clients
      end

      it 'the job and node statuses are marked complete' do
        echo_job_should_complete_on_all_clients
      end
    end

    context 'when running a job that DONKEY fails but FARQUAD and FIONA succeed' do
      before(:each) do
        @command = "ruby -e \"ENV['PUSHY_NODE_NAME'] == 'DONKEY' ? exit(1) : exit(0)\""
        @job1 = start_job(@command, %w{DONKEY FARQUAD FIONA})
      end

      it 'should report success on FARQUAD and FIONA and failed on DONKEY' do
        wait_for_job_complete(@job1['uri'])
        get_job(@job1['uri']).should == {
          'command' => @command,
          'run_timeout' => 3600,
          'nodes' => {
            'succeeded' => [ 'FARQUAD', 'FIONA' ],
            'failed' => [ 'DONKEY' ]
          },
          'status' => 'complete'
        }
      end
    end

    context 'when running a job on FARQUAD and FIONA' do
      before(:each) do
        @job1 = start_job('sleep 2', %w{FARQUAD FIONA})
      end

      context 'and we start a job on DONKEY, FARQUAD and FIONA with a quorum of 2' do
        before(:each) do
          @job2 = start_job(echo_yahoo, %w{DONKEY FARQUAD FIONA}, {'quorum' => 2})
        end

        it 'should fail with reason quorum_failed'  do
          wait_for_job_status(@job2['uri'], 'quorum_failed')
          get_job(@job2['uri']).should == {
            'command' => echo_yahoo,
            'run_timeout' => 3600,
            'nodes' => {
              'nacked' => [ 'FARQUAD', 'FIONA' ],
              'was_ready' => [ 'DONKEY' ]
            },
            'status' => 'quorum_failed'
          }
          job_should_complete('sleep 2', %w{FARQUAD FIONA}, @job1['uri'])
        end
      end
    end

    context 'when running one job on DONKEY' do
      before(:each) do
        File.delete('/tmp/pushytest') if File.exist?('/tmp/pushytest')
        @job1 = start_job('sleep 1', ['DONKEY'])
      end

      context 'and simultaneous job on FARQUAD and FIONA' do
        before(:each) do
          @job2 = start_job(echo_yahoo, ['FARQUAD', 'FIONA'])
        end

        it 'both jobs complete successfully' do
          job_should_complete('sleep 1', %w{DONKEY}, @job1['uri'])
          job_should_complete(echo_yahoo, %w{FARQUAD FIONA}, @job2['uri'])
          IO.read('/tmp/pushytest').should == "YAHOO\n"*2
        end
      end

      context 'and we start a job on DONKEY, FARQUAD, and FIONA with a quorum of 2' do
        before(:each) do
          @job3 = start_job(echo_yahoo, %w{DONKEY FARQUAD FIONA}, options={'quorum' => 2})
          wait_for_job_complete(@job3['uri'])
        end

        it 'should complete on FARQUAD and FIONA' do
          get_job(@job3['uri']).should == {
            'command' => echo_yahoo,
            'run_timeout' => 3600,
            'nodes' => {
              'nacked' => [ 'DONKEY' ],
              'succeeded' => [ 'FARQUAD', 'FIONA' ]
            },
            'status' => 'complete'
          }
          job_should_complete('sleep 1', %w{DONKEY}, @job1['uri'])
        end
      end

      context 'and we start a job on DONKEY and FIONA with a quorum of 2' do
        before(:each) do
          @job4 = start_job(echo_yahoo, %w{DONKEY FIONA}, options={'quorum' => 2})
        end

        it 'should fail with reason quorum_failed' do
          wait_for_job_status(@job4['uri'], 'quorum_failed')
          get_job(@job4['uri']).should == {
            'command' => echo_yahoo,
            'run_timeout' => 3600,
            'nodes' => {
              'nacked' => [ 'DONKEY' ],
              'was_ready' => [ 'FIONA' ]
            },
            'status' => 'quorum_failed'
          }
          job_should_complete('sleep 1', %w{DONKEY}, @job1['uri'])
        end
      end

    end

    context 'with one tied up in a long-running job' do
      before(:each) do
        @job1 = start_job('sleep 1', [ 'DONKEY' ])
      end

      context 'and we try to run a new job on all three nodes' do
        before(:each) do
          @nack_job = start_job(echo_yahoo, [ 'DONKEY', 'FARQUAD', 'FIONA' ])
        end

        it 'nacks the one and fails to run, and old job still completes' do
          wait_for_job_status(@nack_job['uri'], 'quorum_failed')

          nack_job = get_job(@nack_job['uri'])
          nack_job.should == {
            'command' => echo_yahoo,
            'run_timeout' => 3600,
            'nodes' => {
              'nacked' => [ 'DONKEY' ],
              'was_ready' => [ 'FARQUAD', 'FIONA' ]
            },
            'status' => 'quorum_failed'
          }
          job_should_complete('sleep 1', %w{DONKEY}, @job1['uri'])
        end
      end

      context 'and we try to run two other jobs on the node' do
        before(:each) do
          @nack_job = start_job(echo_yahoo, ['DONKEY'])
          @nack_job_2 = start_job(echo_yahoo, ['DONKEY'])
        end

        it 'nacks them both, and old job still completes', :pending do  # pend this for transient mystery failures on CentOS :(

          nack_job = get_job(@nack_job['uri'])
          nack_job.should == {
            'command' => echo_yahoo,
            'run_timeout' => 3600,
            'nodes' => {
              'nacked' => [ 'DONKEY' ]
            },
            'status' => 'quorum_failed'
          }

          nack_job_2 = get_job(@nack_job_2['uri'])
          nack_job_2.should == {
            'command' => echo_yahoo,
            'run_timeout' => 3600,
            'nodes' => {
              'nacked' => [ 'DONKEY' ]
            },
            'status' => 'quorum_failed'
          }
          job_should_complete('sleep 1', [ 'DONKEY' ], @job1['uri'])
        end
      end
    end
  end

  context 'when one client is running a long running job' do
    before :each do
      start_new_clients('DONKEY')
      @long_job = start_job('sleep 5', [ 'DONKEY' ])
    end

    context 'and the client reconfigures' do
      before :each do
        wait_for_job_status(@long_job['uri'], 'running')
        @clients['DONKEY'][:client].reconfigure
      end

      it 'the job still completes' do
        job_should_complete('sleep 5', [ 'DONKEY' ], @long_job['uri'])
      end
    end
  end

  # This was moved to the bottom because it seems to be adversely affecting other tests
  # TODO Figure out why this breaks other tests and fix it
  context 'when one client is running a long running job' do
    before :each do
      start_new_clients('DONKEY')
      @long_job = start_job('sleep 20', [ 'DONKEY' ])
    end

    context 'and the server goes down and comes back up', :pending => (not (!!Pedant.config[:running_from_backend])) do
      # This should only run on a maching that runs backend services
      # because we currently shut down the pushy server by shelling
      # out; this doesn't work on frontend machines because there's no
      # service to shell out to.
      before :each do
        restart_server
        wait_for_server_restart
        wait_for_node_status("online", "DONKEY")
        wait_for_node_to_come_out_of_rehab("DONKEY")
      end

      it 'the client should abort and then be able to run another job, and the job should be set to crashed' do
        start_echo_job_on_all_clients
        echo_job_should_complete_on_all_clients
        wait_for_job_status(@long_job['uri'], 'crashed')
      end
    end
  end

  context 'bad input' do
    it '404s when retrieving a nonexistent job' do
      get(api_url('pushy/jobs/abcdefabcdef807f32d9572f8aafbd03'), admin_user) do |response|
        response.should look_like({:status=>404})
        # TODO return JSON error body
      end
    end
  end
end
