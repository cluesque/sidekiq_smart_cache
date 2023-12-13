require 'test_helper'

class RedisTest < ActiveSupport::TestCase
  setup do
    SidekiqSmartCache.redis.flushdb
  end

  test 'basic set and get' do
    assert_nil SidekiqSmartCache.redis.get('narf')

    SidekiqSmartCache.redis.set('narf', 'blah')
    assert_equal SidekiqSmartCache.redis.get('narf'), 'blah'
  end

  test 'arrayify_args' do
    assert_equal SidekiqSmartCache.redis.arrayify_args(['bar', { nx: true, ex: 60 }]), %w[bar NX EX 60]
  end

  test 'setnx' do
    assert_nil SidekiqSmartCache.redis.get('narf')

    # setnx returns true when the key is being set
    assert SidekiqSmartCache.redis.set('narf', 'blah', nx: true)
    assert_equal SidekiqSmartCache.redis.get('narf'), 'blah'

    # returns false when its already set
    refute SidekiqSmartCache.redis.set('narf', 'bunk', nx: true)
    assert_equal SidekiqSmartCache.redis.get('narf'), 'blah'

  end

  test 'expiring keys' do
    assert_nil SidekiqSmartCache.redis.get('narf')

    assert SidekiqSmartCache.redis.set('narf', 'blah', nx: true, ex: 60)
    assert_equal SidekiqSmartCache.redis.get('narf'), 'blah'
    # confirm the expiration was set as expected
    assert_equal SidekiqSmartCache.redis.ttl('narf'), 60

    # returns false when its already set
    refute SidekiqSmartCache.redis.set('narf', 'bunk', nx: true)
    assert_equal SidekiqSmartCache.redis.get('narf'), 'blah'

    # another way of making a key expire
    assert SidekiqSmartCache.redis.set('blah', 'bart') && SidekiqSmartCache.redis.expire('blah', 42)
    assert_equal SidekiqSmartCache.redis.ttl('blah'), 42

  end

  test 'brpop' do
    SidekiqSmartCache.redis.lpush('narf', 'bunk')
    duration = Benchmark.realtime do
      assert_equal SidekiqSmartCache.redis.brpop('narf', timeout: 2), %w[narf bunk]
    end
    assert_includes 0.0..0.1, duration, 'Should finish immediately'

    duration = Benchmark.realtime do
      refute SidekiqSmartCache.redis.brpop('narf', timeout: 2) # returns nil on timeout
    end
    assert_includes 1.5..2.5, duration, 'Should time out'
  end
end