require 'test_helper'

class SidekiqSmartCache::Test < ActiveSupport::TestCase
  setup do
    Sidekiq::Testing.inline!
    SidekiqSmartCache.redis.call("FLUSHDB")
    @doohickey = Doohickey.create!(name: 'foo bar')
    assert_equal @doohickey.name, 'foo bar'
  end

  test 'model method invocation' do
    promise = SidekiqSmartCache::Promise.new(object: @doohickey, method: :name, expires_in: 1)
    found_name = promise.execute_and_wait!(1)
    assert_equal @doohickey.name, found_name
  end

  test 'model method with an argument' do
    promise = SidekiqSmartCache::Promise.new(object: @doohickey, method: :make_a_thing, args: ['bas'], expires_in: 1)
    answer = promise.execute_and_wait!(1)
    assert_equal 'foo bar bas', answer
  end

  test 'ready_within?' do
    promise = SidekiqSmartCache::Promise.new(object: @doohickey, method: :make_a_thing, args: ['bunk'], expires_in: 1)
    assert promise.ready_within?(1.second)
    assert_equal 'foo bar bunk', promise.value
  end

  test 'stale results' do
    start_time = Time.now
    promise = SidekiqSmartCache::Promise.new(object: @doohickey, method: :make_a_thing, args: ['bunk'], expires_in: 1)
    assert_equal 'foo bar bunk', promise.execute_and_wait(1.second)
    travel 4.seconds

    promise2 = SidekiqSmartCache::Promise.new(object: @doohickey, method: :make_a_thing, args: ['bunk'], expires_in: 1)
    assert promise2.stale_value_available?
    assert_equal 'foo bar bunk', promise.existing_value(allow_stale: true)
    assert_in_delta start_time, promise2.result_created_at, 0.1
  end

  test 'nil as a result' do
    promise = SidekiqSmartCache::Promise.new(klass: Doohickey, method: :take_a_moment, args: [0, nil])
    duration = Benchmark.realtime do
      assert_nil promise.execute_and_wait!(10.seconds)
    end
    assert_includes 0.0..0.25, duration, 'should be instant'
  end

  test 'structured result' do
    structured_answer = {'bar' => 'bas', 'bunk' => { 'bust' => 'bart', 'blah' => 42, 'nuthin' => nil } }
    promise = SidekiqSmartCache::Promise.new(klass: Doohickey, method: :take_a_moment, args: [0, structured_answer])
    duration = Benchmark.realtime do
      assert_equal structured_answer, promise.execute_and_wait!(10.seconds)
    end
    assert_includes 0.0..0.25, duration, 'should be instant'
  end
end
