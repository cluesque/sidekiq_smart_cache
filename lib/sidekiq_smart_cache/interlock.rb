module SidekiqSmartCache
  class Interlock
    delegate :redis, to: SidekiqSmartCache
    attr_accessor :cache_tag, :job_interlock_timeout

    def initialize(cache_tag, job_interlock_timeout=nil)
      @cache_tag = cache_tag
      @job_interlock_timeout = job_interlock_timeout
    end

    def key
      cache_tag + '/in-progress'
    end

    def working?
      redis.get(key)
    end

    def lock_job?
      redis.set(key, 'winner!', nx: true) && redis.expire(key, job_interlock_timeout)
    end

    def clear
      redis.del(key)
    end
  end
end
