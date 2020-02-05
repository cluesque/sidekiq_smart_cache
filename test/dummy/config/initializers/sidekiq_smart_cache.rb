Rails.configuration.to_prepare do
  SidekiqSmartCache.logger = Rails.logger
  SidekiqSmartCache.redis_pool = Sidekiq.redis_pool
  SidekiqSmartCache.cache_prefix = ENV['RAILS_CACHE_ID']
end
