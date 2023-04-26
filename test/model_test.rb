require 'test_helper'

class ModelTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Testing.inline!
    Sidekiq.redis(&:flushdb)
    @doohickey = Doohickey.create!(name: 'foo bar')
    assert_equal @doohickey.name, 'foo bar'
  end

  test 'cache tag generation' do
    tag = @doohickey.median_thromboid_density_cache_tag('foo', 'bar', 1.5)
    assert_match %r{Doohickey/#{@doohickey.id}/median_thromboid_density}, tag

    tag2 = @doohickey.median_thromboid_density_cache_tag('foo', 'bas', 1.5)
    refute_equal tag, tag2, 'different arguments should mean different tags'
  end

  test 'direct calculation' do
    time = Benchmark.realtime do
      assert_equal 'foo bar foo bas', @doohickey.median_thromboid_density_without_caching('foo', 'bas', 1.5)
    end
    assert_in_delta time, 1.5, 0.2
  end

  test 'hitting on cache' do
    assert_nil @doohickey.median_thromboid_density_if_available('foo', 'bas', 1.5)
    time = Benchmark.realtime do
      assert_equal 'foo bar foo bas', @doohickey.refresh_median_thromboid_density('foo', 'bas', 1.5)
    end
    assert_in_delta time, 1.5, 0.2

    time = Benchmark.realtime do
      assert_equal 'foo bar foo bas', @doohickey.median_thromboid_density('foo', 'bas', 1.5)
    end
    assert_in_delta time, 0, 0.2
  end
end
