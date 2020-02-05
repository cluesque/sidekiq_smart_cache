require 'test_helper'

class SidekiqSmartCache::Test < ActiveSupport::TestCase
  setup do
    Sidekiq::Testing.inline!
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
end
