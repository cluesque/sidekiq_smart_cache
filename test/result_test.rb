require 'test_helper'

class ResultTest < ActiveSupport::TestCase
  setup do
    SidekiqSmartCache.redis.flushdb
  end

  test 'storing and retrieving string result' do
    assert_nil Result.load_from('narf')
    Result.persist('narf', 'blah', 10.seconds)
    result = Result.load_from('narf')
    assert result.fresh?
    refute result.stale?
    assert_equal result.value, 'blah'
  end
end