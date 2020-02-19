module SidekiqSmartCache
  class Redis
    def initialize(pool)
      @pool = pool
    end

    def job_completion_key(key)
      key + '/done'
    end

    def send_done_message(key)
      lpush(job_completion_key(key), 'done')
      expire(job_completion_key(key), 1)
    end

    def wait_for_done_message(key, timeout)
      return true if defined?(Sidekiq::Testing) && Sidekiq::Testing.inline?
      if brpop(job_completion_key(key), timeout.to_i)
        # log_msg("got done message for #{key}")
        send_done_message(key) # put it back for any other readers
        true
      end
    end

    def log_msg(msg) # WIP all this
      Rails.logger.info("#{Time.now.iso8601(3)} #{Thread.current[:name]} redis #{msg}")
    end

    def method_missing(name, *args)
      @pool.with do |r|
        if r.respond_to?(name)
          retryable = true
          begin
            # log_msg("#{name} #{args}")
            r.send(name, *args)
            # WIP simplify to the above when not logging
            # r.send(name, *args)a.tap do |val|
            #   log_msg("#{name} #{args} -> #{val}")
            # end
          # stolen from sidekiq - Thanks Mike!
        rescue ::Redis::CommandError => ex
            # 2550 Failover can cause the server to become a replica, need
            # to disconnect and reopen the socket to get back to the primary.
            if retryable && ex.message =~ /READONLY/
              r.disconnect!
              retryable = false
              retry
            end
            raise
          end
        else
          super
        end
      end
    end
  end
end
