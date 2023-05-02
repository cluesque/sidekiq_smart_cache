module SidekiqSmartCache
  BLOCKING_COMMANDS = %i[ brpop ].freeze
  COMMANDS = BLOCKING_COMMANDS + %i[ get set lpush expire flushdb del ].freeze

  ERROR_TO_CATCH = if defined?(::RedisClient)
    ::RedisClient::CommandError
  else
    ::Redis::CommandError
  end

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
        if COMMANDS.include? name
          retryable = true
          begin
            # log_msg("#{name} #{args}")
            if r.respond_to?(name)
              # old redis gem implements methods including `brpop` and `flusdb`
              r.send(name, *args)
            elsif BLOCKING_COMMANDS.include? name
              # support redis-client semantics
              begin
                r.blocking_call(args[1], name.to_s.upcase, args[0], 0)
              rescue ::RedisClient::TimeoutError
                nil # quietly return nil in this case
              end
            else
              r.call(name.to_s.upcase, *args)
            end
            # WIP simplify to the above when not logging
            # r.send(name, *args)a.tap do |val|
            #   log_msg("#{name} #{args} -> #{val}")
            # end
            # stolen from sidekiq - Thanks Mike!
            # Quietly consume this one and return nil
          rescue ERROR_TO_CATCH => ex
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
