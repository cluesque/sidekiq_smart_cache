require 'test_helper'

class ConcurrentExamplesTest < ActiveSupport::TestCase
  # This set of tests rely on live sidekiq worker threads
  # executing concurrently with the test threads
  # It also has a sequence of moments in time, with one second granularity
  # (one of the things we rely on is redis read timeouts, which are pretty coarse)
  # ... so the tests take 13 seconds to run

  # Test Scenarios:
  # Time:      1      2      3      4      5      6      7      8
  # Scenario                                                         Description
  # A          |o----------->|                                       Cache miss, waits for response
  # B                 |----->|                                       Second request waits for first calculation
  # C                              >|<                               Cache hit, immediate response
  # D                                             |o----------->|    Stale result recalculated
  #
  # Time:     11     12     13
  # E         |o------x                                              Requester E starts calculation, times out before response complete
  # F                 |----->|                                       Requester F benefits from result abandoned by E

  EXAMPLES = [
    # label, request_start, request_timeout, expect_answer, expect_duration
    ['A', 1, 3, 'narf 1', 3],
    ['B', 2, 3, 'narf 1', 3],
    ['C', 4, 3, 'narf 1', 4],
    ['D', 6, 3, 'narf 2', 8],
    ['E', 11, 1, nil, 12],
    ['F', 12, 3, 'narf 3', 13],
  ]

  setup do
    Sidekiq.configure_client do |cfg|
      cfg.logger = Rails.logger
      cfg.redis = { size: 25}
      cfg.queues = ['default']
    end

    Sidekiq::Testing.disable!

    SidekiqSmartCache.redis.call("FLUSHDB")
    @launcher = Sidekiq::Launcher.new(Sidekiq.default_configuration);0
    @launcher.run
  end

  teardown do
    @launcher.stop
  end

  class CacheExample
    TIMESLICE = Doohickey::TIME_UNIT
    FRESH_FOR = (TIMESLICE * 2).seconds

    attr_accessor :label, :request_start, :request_timeout, :expect_answer, :expect_duration, :answer
    def initialize(label, request_start, request_timeout, expect_answer, expect_duration)
      @label = label
      @request_start = request_start
      @request_timeout = request_timeout
      @expect_answer = expect_answer
      @expect_duration = expect_duration
      start
      self
    end

    def start
      @start_time = Time.now
      @thread = Thread.new do
        sleep (request_start - 1.0) * TIMESLICE # time starts at 1.0, so subtract that
        promise = SidekiqSmartCache::Promise.new(klass: Doohickey, method: :do_a_thing, expires_in: FRESH_FOR)
        begin
          @answer = promise.execute_and_wait!(request_timeout * TIMESLICE)
        rescue SidekiqSmartCache::TimeoutError
          @timed_out = true
        end
        @end_time = Time.now
      end
    end

    def join
      @thread.join
    end

    attr_accessor :start_time, :end_time
  end

  test 'concurrent execution examples' do
    Doohickey.delete_all
    examples = EXAMPLES.map do |ex|
      CacheExample.new(*ex)
    end
    examples.each(&:join) # wait for them to finish
    examples.each do |example|
      if example.expect_answer.nil?
        time_tolerance = 1.5 # redis timeout is not so precise
        assert_nil example.answer, "Example #{example.label} expected no answer, got #{example.answer}"
      else
        time_tolerance = 0.5 # actual invocation time more precise
        assert_equal example.expect_answer, example.answer, "Example #{example.label}"
      end
      # assert_equal example.end_time_slice, example.expect_duration
      assert_in_delta example.end_time, example.start_time + (example.expect_duration - 1) * CacheExample::TIMESLICE, time_tolerance,
        "Example #{example.label} started #{example.start_time.strftime("%H:%M:%S.%L")} duration #{example.expect_duration} ended #{example.end_time.strftime("%H:%M:%S.%L")}"
    end
  end

  test 'timing out' do
    promise = SidekiqSmartCache::Promise.new(klass: Doohickey, method: :do_a_thing, expires_in: 2.seconds, args: [3.0])
    duration = Benchmark.realtime do
      refute promise.ready_within?(1.second)
    end
    assert_includes 1.0..3.25, duration, "Should time out after about a second"
    assert promise.timed_out?
  end

  test 'asynchronous start' do
    promise = SidekiqSmartCache::Promise.new(klass: Doohickey, method: :do_a_thing, expires_in: 2.seconds)
    promise.start
    start_sleep = 1.0
    sleep start_sleep
    duration = Benchmark.realtime do
      assert promise.ready_within?(Doohickey::DEFAULT_DURATION)
    end
    assert_in_delta Doohickey::DEFAULT_DURATION, duration + start_sleep, 0.5
    refute promise.timed_out?
  end

  test 'model timeout and then succeed' do
    doohickey = Doohickey.create!(name: 'fun')
    promise = doohickey.median_thromboid_density_promise('foo', 'bas', 3.0).start
    duration = Benchmark.realtime do
      assert_raises(SidekiqSmartCache::TimeoutError) do
        promise.fetch!(1.second)
      end
    end
    assert_includes 1.0..2.5, duration, "Should timeout after about a second"

    duration = Benchmark.realtime do
      assert_equal 'fun foo bas', promise.fetch!(5.seconds)
    end
    assert_includes 0.5..2.0, duration, "Should finish after about two seconds" # more leeway for errors adding up
  end

  test 'wait_for_done_message without exception' do
    promise = SidekiqSmartCache::Promise.new(klass: Doohickey, method: :take_a_moment, args: [4.0])
    duration = Benchmark.realtime do
      assert_nil promise.execute_and_wait(1)
    end
    assert_includes 0.5..2.5, duration, "Should finish after about a second"
  end
end
