# -*- indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
#
# Author:: Steven Grady (<steven.grady@erlang-solutions.com>)

# @copyright Copyright 2014 Chef Software, Inc. All Rights Reserved.
#
# This file is provided to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file
# except in compliance with the License. You may obtain
# a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.
#

require 'httpclient'
require 'thread'
require 'typhoeus'

shared_context "sse_support" do
  class Event < Struct.new(:name, :id, :json); end

  # Adapted from github.com/conjurinc/sse-client-ruby -- should really just use that package;
  # but based on code inspection, it will miss the last event if it doesn't end with a "\n\n".
  # I suspect it was assuming an infinite stream.
  class EventParser
    def initialize
      @buffer = ''
      @events = []
    end

    attr_reader :events

    def feed(chunk, final = false)
      @buffer << chunk
      process_events(final)
    end

    def process_events(final)
      while i = @buffer.index("\n\n")
        process_event(@buffer.slice!(0..i))
      end
      if final
        process_event(@buffer)
      end
    end

    def process_event(evstr)
      data, id, name = [], nil, nil
      evstr.lines.map(&:chomp).each do |l|
        field, value = case l
          when /^:/ then
            next # comment, do nothing
          when /^(.*?):(.*)$/ then
            [$1, $2]
          else
            [l, ''] # this is what the spec says, I swear!
        end
        # spec allows one optional space after the colon
        value = value[1..-1] if value.start_with? ' '
        case field
          when 'data' then
            data << value
          when 'id' then
            id = value
          when 'event' then
            name = value.to_sym
          when 'retry' then
            @retry = value.to_i
        end
      end
      @last_event_id = id
      @events << Event.new(name, id, JSON.parse(data.join("\n"))) if name != nil
    end

    def events_so_far
      evs = @events
      @events = []
      evs
    end
  end

  class EventStreamOld
    def initialize(url, user, last_id, receive_timeout)
      host = URI.parse(url).host
      @evs = []
      @complete = false
      @client = HTTPClient.new
      @client.receive_timeout = receive_timeout
      # Certificate is self-signing -- if we don't disable certificate verification, this won't work
      @client.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE
      @queue = Queue.new

      auth_headers = user.signing_headers(:GET, url, "")
      require 'chef/version'
      headers =
        {
          'Accept' => 'text/event-stream',
          'User-Agent' => 'chef-pedant rspec tests',
          'X-Chef-Version' => Chef::VERSION,
          'Host' => host,
          'Cache-Control' => 'no-cache'   # spec says clients should always set this
        }
      headers.merge!(auth_headers)
      if last_id then
          headers.merge!({'Last-Event-ID' => last_id})
      end
      
      @ep = EventParser.new
      Thread.new {
        conn = @client.get_async(url, :header => headers)
        resp = conn.pop
        content_io = resp.content
        while ! conn.finished?
          begin
            str = content_io.readpartial(4096)
            if str
              @queue << str
            end
          rescue EOFError
          end
        end
        # Get anything remaining out of the pipe
        str = content_io.read
        if str
          @queue << str
        end
        @queue << :done
      }
    end

    attr_reader :complete

    def get_streaming_events
      while ! @queue.empty?
        el = @queue.pop
        if el == :done
          @ep.feed("", true)
          @complete = true
        else
          @ep.feed(el)
        end
      end
      @evs += @ep.events_so_far
      @evs
    end

    def close
        @client.reset_all
    end

  end

  class EventStream
    def initialize(url, user, last_id, receive_timeout)
      host = URI.parse(url).host
      @evs = []
      @complete = false
      # XXX May need to disable SSL verification, if possible
      @queue = Queue.new

      auth_headers = user.signing_headers(:GET, url, "")
      require 'chef/version'
      headers =
        {
          'Accept' => 'text/event-stream',
          'User-Agent' => 'chef-pedant rspec tests',
          'X-Chef-Version' => Chef::VERSION,
          'Host' => host,
          'Cache-Control' => 'no-cache'   # spec says clients should always set this
        }
      headers.merge!(auth_headers)
      if last_id then
          headers.merge!({'Last-Event-ID' => last_id})
      end
      
      @ep = EventParser.new
      Thread.new {
        req = Typhoeus::Request.new(
          url,
          headers: headers,
          timeout: receive_timeout,
          verbose: true
        )
        req.on_body do |chunk|
          @queue << chunk
        end
        req.on_complete do |response|
          @queue << :done
        end
        req.run
      }
    end

    attr_reader :complete

    def get_streaming_events
      while ! @queue.empty?
        el = @queue.pop
        if el == :done
          @ep.feed("", true)
          @complete = true
        else
          @ep.feed(el)
        end
      end
      @evs += @ep.events_so_far
      @evs
    end

    def close
        @client.reset_all
    end

  end

  def expect_start(e, command, run_timeout, quorum, node_count, username, job = nil)
    e.name.should == :start
    e.json['command'].should == command
    e.json['run_timeout'].should == run_timeout
    e.json['quorum'].should == quorum
    e.json['node_count'].should == node_count
    e.json['user'].should == username
    e.json['job'].should == job if job
  end

  def expect_quorum_vote(e, node, status)
    e.name.should == :quorum_vote
    e.json['status'].should == status
    check_node(e, node)
  end

  def expect_quorum_succeeded(e)
    e.name.should == :quorum_succeeded
  end

  def expect_run_start(e, node)
    e.name.should == :run_start
    check_node(e, node)
  end

  def expect_run_complete(e, node, status)
    e.name.should == :run_complete
    e.json['status'].should == status
    check_node(e, node)
  end

  def expect_job_complete(e, status, job = nil)
    e.name.should == :job_complete
    e.json['status'].should == status
    e.json['job'].should == job if job
  end

  def expect_rehab(e, node)
    e.name.should == :rehab
    check_node(e, node)
  end

  def expect_summary(e, command, status, run_timeout, succeeded, failed)
    e.name.should == :summary
    e.json['command'].should == command
    e.json['status'].should == status
    e.json['run_timeout'].should == run_timeout
    created_at = Time.parse(e.json['created_at'])
    updated_at = Time.parse(e.json['updated_at'])
    updated_at.should >= created_at
    e.json['nodes']['succeeded'].should == succeeded
    e.json['nodes']['failed'].should == failed
  end

  def parse_complete_stream(s)
    ep = EventParser.new()
    ep.feed(s, true)
    ep.events
  end

  # Validate standard events; as a side-effect, save the parsed json field
  def validate_events(numEvents, evs)
    require 'pp'
    pp evs
    evs.length.should == numEvents
    # All ids are unique
    evs.map(&:id).uniq.length.should == evs.length
    # All events have (parsable) timestamps
    ts = evs.map {|e| Time.parse(e.json['timestamp'])}
    # All timestamps are unique
    ts.uniq.length.should == ts.length
    # All timestamps are in increasing order
    ts.sort.should == ts
  end

  def expect_valid_response(numEvents, response)
    response.should look_like({ :status => 200 })
    evs = parse_complete_stream(response.body)
    validate_events(numEvents, evs)
    evs
  end
end
