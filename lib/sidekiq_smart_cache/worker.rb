require 'sidekiq'

module SidekiqSmartCache
  class Worker
    include Sidekiq::Worker
    delegate :redis, to: SidekiqSmartCache

    def perform(klass, instance_id, method, args, cache_tag, expires_in)
      all_args = [method]
      if args.is_a?(Array)
        all_args += args
      elsif args
        all_args << args
      end
      subject = Object.const_get(klass)
      subject = subject.find(instance_id) if instance_id
      result = subject.send(*all_args)
      raise 'nil results not (yet) supported' if result.nil?
      redis.set(cache_tag, result)
      redis.expire(cache_tag, expires_in)
      redis.send_done_message(cache_tag)
      result
    ensure
      # remove the interlock key
      Interlock.new(cache_tag).clear
    end
  end
end
