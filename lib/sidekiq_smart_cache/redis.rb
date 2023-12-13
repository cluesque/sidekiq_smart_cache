module SidekiqSmartCache
  BLOCKING_COMMANDS = %i[ brpop ].freeze
  COMMANDS = BLOCKING_COMMANDS + %i[get set lpush expire flushdb del ttl].freeze

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
      "#{key}/done"
    end

    def send_done_message(key)
      lpush(job_completion_key(key), 'done')
      expire(job_completion_key(key), 1)
    end

    def wait_for_done_message(key, timeout)
      return true if defined?(Sidekiq::Testing) && Sidekiq::Testing.inline?

      return unless brpop(job_completion_key(key), timeout: timeout.to_i)

      # log_msg("got done message for #{key}")
      send_done_message(key) # put it back for any other readers
      true
    end

    def log_msg(msg) # WIP all this
      Rails.logger.info("#{Time.now.iso8601(3)} #{Thread.current[:name]} redis #{msg}")
    end

    # In support of syntax like redis.set('foo', 'bar', nx: true, ex: 60)
    # the new client wants that called like redis.set('foo', 'bar', 'NX', 'EX', '60')
    def arrayify_args(args)
      out = []
      args.each do |arg|
        if arg.is_a?(Hash)
          arg.each do |kw, val|
            # nx: true becomes 'NX'
            if val == true
              out << kw.upcase.to_s
            elsif val
              # ex: 60 becomes ['EX', '60']
              out << kw.upcase.to_s
              out << val.to_s
            end
          end
        else
          out << arg
        end
      end
      out.presence
    end

    # Defining methods like `redis.set('foo', 'bar')`
    COMMANDS.each do |name|
      define_method(name) do |*args|
        @pool.with do |r|
          retryable = true
          begin
            # log_msg("#{name} #{args}")
            if defined?(::Redis) && r.is_a?(::Redis)
              if r.respond_to?(name)
                # old redis gem implements methods including `brpop` and `flusdb`
                r.send(name, *args)
              else
                r.call(name.to_s.upcase, *args)
              end
            elsif BLOCKING_COMMANDS.include? name
              # support redis-client semantics
              make_blocking_call(r, name, *args)
            else
              # Translate keyword args to new style array on RedisClient (even wrapped by Sidekiq)
              r.send(name, *arrayify_args(args))
            end
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
        end
      end
    end

    def make_blocking_call(r, name, *args)
      # The Redis `brpop` implementation seems to allow timeout to be the last argument
      # or a key in a hash `timeout: 5`, so:
      # `r.brpop('key1', 'key2', 5)` - wait five seconds for either queue
      # `r.brpop('key1', 'key2', timeout: 5)` - same
      # `r.brpop('key1', 'key2')` - wait forever on either queue
      timeout = if args.last.is_a?(Hash)
        options = args.pop
        options[:timeout]
      else
        args.pop
      end

      # With RedisClient, the doc is a little thin, but it looks like we want to start with the timeout
      # then the verb, then the array of keys
      # and end with ... a 0?
      blocking_call_args = [timeout, name.to_s.upcase] + args + [0]
      r.blocking_call(*blocking_call_args)
    rescue ::RedisClient::TimeoutError
      nil # quietly return nil in this case
    end
  end
end
