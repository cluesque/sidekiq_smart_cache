module SidekiqSmartCache
  class Promise
    attr_accessor :klass, :object_param, :method, :expires_in, :args, :job_interlock_timeout
    attr_accessor :timed_out
    delegate :redis, :log, to: SidekiqSmartCache
    delegate :working?, to: :interlock
    delegate :value, to: :result
    delegate :created_at, to: :result, prefix: true

    def initialize(klass: nil, object: nil, object_param: nil, method:, args: nil,
                   cache_tag: nil, expires_in: 1.hour, job_interlock_timeout: nil)
      if object
        @klass = object.class.name
        @object_param = object.to_param
      elsif klass
        @klass = klass.to_s
        @object_param = object_param
      else
        raise "Must provide either klass or object"
      end
      raise "Must provide method" unless method
      @method = method.to_s
      @expires_in = expires_in.to_i
      @job_interlock_timeout = job_interlock_timeout || @expires_in
      @args = args
      @cache_tag = cache_tag
    end

    def cache_tag
      @cache_tag ||= begin
        [
          klass,
          (object_param || '.'),
          method,
          (Digest::MD5.hexdigest(args.compact.to_json) if args.present?)
        ].compact * '/'
      end
    end

    def interlock
      @_interlock ||= Interlock.new(cache_tag, job_interlock_timeout)
    end

    def perform_now
      Worker.new.perform(klass, object_param, method, args, cache_tag, expires_in)
    end

    def enqueue_job!
      Worker.perform_async(klass, object_param, method, args, cache_tag, expires_in)
    end

    def execute_and_wait!(timeout, stale_on_timeout: false)
      execute_and_wait(timeout, raise_on_timeout: true, stale_on_timeout: stale_on_timeout)
    end

    def result
      Result.load_from(cache_tag)
    end

    def stale_value_available?
      !!result&.stale?
    end

    def existing_value(allow_stale: false)
      if (existing = result) && (allow_stale || existing.fresh?)
        existing.value
      end
    end

    def ready_within?(timeout)
      execute_and_wait(timeout)
      !timed_out
    end

    def timed_out?
      !!timed_out
    end

    def start
      # Start a job if no other client has
      if interlock.lock_job?
        log('promise enqueuing calculator job')
        enqueue_job!
      else
        log('promise calculator job already working')
      end
      self # for chaining
    end

    def execute_and_wait(timeout, raise_on_timeout: false, stale_on_timeout: false)
      previous_result = result
      if previous_result&.fresh?
        # found a previously fresh message
        @timed_out = false
        return previous_result.value
      else
        start

        # either a job was already running or we started one, now wait for an answer
        if redis.wait_for_done_message(cache_tag, timeout.to_i)
          # ready now, fetch it
          log('promise calculator job finished')
          @timed_out = false
          result.value
        elsif previous_result && stale_on_timeout
          log('promise timed out awaiting calculator job, serving stale')
          previous_result.value
        else
          log('promise timed out awaiting calculator job')
          @timed_out = true
          raise TimeoutError if raise_on_timeout
        end
      end
    end

    alias_method :fetch!, :execute_and_wait!
    alias_method :fetch, :execute_and_wait

  end
end
