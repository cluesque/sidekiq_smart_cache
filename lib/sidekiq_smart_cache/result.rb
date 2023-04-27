class Result
  class << self
    delegate :redis, :allowed_classes, to: SidekiqSmartCache
  end
  attr_accessor :value, :valid_until, :created_at, :cache_prefix

  def self.persist(cache_tag, value, expires_in)
    structure = {
      value: value,
      created_at: Time.now,
      valid_until: Time.now + expires_in,
      cache_prefix: SidekiqSmartCache.cache_prefix
    }
    result_lifetime = 1.month.to_i # ??? maybe a function of expires_in ???
    redis.set(cache_tag, structure.to_yaml)
    redis.expire(cache_tag, result_lifetime)
  end

  def self.load_from(cache_tag)
    raw = redis.get(cache_tag)
    new(YAML.safe_load(raw,  permitted_classes: allowed_classes)) if raw
  end

  def initialize(result)
    @value = result[:value]
    @created_at = result[:created_at]
    @valid_until = result[:valid_until]
    @cache_prefix = result[:cache_prefix]
  end

  def fresh?
    !stale?
  end

  def stale?
    (Time.now > valid_until) || (cache_prefix != SidekiqSmartCache.cache_prefix)
  end
end
