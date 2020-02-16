require "sidekiq_smart_cache/worker"
require "sidekiq_smart_cache/interlock"
require "sidekiq_smart_cache/model"
require "sidekiq_smart_cache/promise"
require "sidekiq_smart_cache/redis"
require "sidekiq_smart_cache/result"

module SidekiqSmartCache
  class TimeoutError < StandardError; end

  class << self
    attr_accessor :cache_prefix, :redis_pool, :logger, :log_level
  end

  def self.log(message)
    logger.send((log_level || :info), message) if logger
  end

  def self.redis
    @redis ||= Redis.new(redis_pool)
  end
end
