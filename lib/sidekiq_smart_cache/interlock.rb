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
      redis.call("GET", key)
    end

    def lock_job?
      redis.call("SET", key, 'winner!', nx: true) && redis.call("EXPIRE", key, job_interlock_timeout)
    end

    def clear
      redis.call("DEL", key)
    end
  end
end
