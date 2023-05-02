require 'active_support/concern'
module SidekiqSmartCache::Model
  extend ActiveSupport::Concern

  module ClassMethods
    # Takes a class or instance action, makes it operate lazy-loaded through a cache, and adds a couple of related actions to the class.
    #
    # === Example
    #
    # A User class has a active_user_count class method that is expensive to calculate
    #
    # Declaring <tt>make_class_action_cacheable :active_user_count</tt> will add:
    #
    # * <tt>User.active_user_count_without_caching</tt> - always performs the full calculation synchronously, doesn't touch the cache.
    # * <tt>User.refresh_active_user_count</tt> - always performs the full calculation synchronously, populating the cache with the new value.
    # * <tt>User.active_user_count</tt> (the original name) - will now fetch from the cache, only recalculating if the cache is absent or stale.
    # * <tt>User.active_user_count_if_available</tt> will now fetch from the cache but not recalculate, returning nil if the cache is absent or stale.
    # * <tt>User.active_user_count_cache_tag</tt> - the cache tag used to store calculated results. Probably not useful to clients.
    # * <tt>User.active_user_count_promise</tt> - returns a promise object
    #
    # Call <tt>promise.fetch(5.seconds)</tt> to wait up to five seconds for a new value, returning nil on timeout
    # Call <tt>promise.fetch!(5.seconds)</tt> to wait up to five seconds for a new value, raising SidekiqSmartCache::TimeoutError on timeout
    #
    # Use <tt>make_instance_action_cacheable</tt> for the equivalent set of instance methods.
    # Your models must respond to <tt>to_param</tt> with a unique string suitable for constructing a cache key.
    # The class must respond to <tt>find(param)</tt> and return an object that responds to the method.
    #
    # === Options
    # [:cache_tag]
    #   Specifies the cache tag to use.
    #   A default cache tag will include the cache_prefix, so will implicitly flush on each release.
    #
    # [:expires_in]
    #   Specifies a period after which a cached result will be invalid. Default one hour.
    #
    # [:job_interlock_timeout]
    #   When a new value is needed, prevents new refresh jobs from being dispatched.
    #
    # Option examples:
    #   make_action_cacheable :active_user_count, expires_in: 12.hours, job_interlock_timeout: 10.minutes
    #   make_instance_action_cacheable :median_post_length, expires_in: 1.hour, job_interlock_timeout: 1.minute
    delegate :cache_prefix, to: SidekiqSmartCache

    def make_action_cacheable(name, options = {})
      cache_tag = options[:cache_tag] || [cache_prefix, self.name, name].join('.')
      cache_options = options.slice(:expires_in, :job_interlock_timeout)
      instance_method = options[:instance_method]
      without_caching_name = "#{name}_without_caching"
      promise_method_name = "#{name}_promise"

      promise_method = ->(*args) do
        promise_args = cache_options.merge(
          method: without_caching_name,
          args: args
        )

        if instance_method
          promise_args[:klass] = self.class.name
          promise_args[:object_param] = to_param
        else
          promise_args[:klass] = self.name
        end
        SidekiqSmartCache::Promise.new(**promise_args)
      end

      if_available_method = ->(*args) do
        send(promise_method_name, *args).existing_value
      end

      cache_tag_method = ->(*args) do
        send(promise_method_name, *args).cache_tag
      end

      with_caching_method = ->(*args) do
        send(promise_method_name, *args).fetch(24.hours) # close enough to forever?
      end

      without_caching_method = ->(*args) do
        method(name).super_method.call(*args)
      end

      refresh_method = ->(*args) do
        send(promise_method_name, *args).perform_now
      end

      prefix_module = Module.new
      prefix_module.send(:define_method, "#{name}_if_available", if_available_method)
      prefix_module.send(:define_method, "#{name}_cache_tag", cache_tag_method)
      prefix_module.send(:define_method, name, with_caching_method)
      prefix_module.send(:define_method, without_caching_name, without_caching_method)
      prefix_module.send(:define_method, promise_method_name, promise_method)
      prefix_module.send(:define_method, "refresh_#{name}", refresh_method)

      if instance_method
        prepend prefix_module
      else
        singleton_class.prepend prefix_module
      end
    end

    def make_class_action_cacheable(name, options = {})
      make_action_cacheable(name, options)
    end

    def make_instance_action_cacheable(name, options = {})
      make_action_cacheable(name, options.merge(instance_method: true))
    end
  end
end
