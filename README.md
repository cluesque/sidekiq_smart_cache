# SidekiqSmartCache

Generate and cache objects using sidekiq, with thundering herd prevention and client timeouts.

Say you have a resource that's expensive to calculate (a heavy database query) and would like to use it in a web page.

But you'd rather the web page show an empty value (or a "check back later" placeholder) than take too long to render.

And you'd like to ensure that if there are multiple actions requesting that page at once, that the database only has to fill the query once.  (You want to prevent a [thundering herd problem](https://en.wikipedia.org/wiki/Thundering_herd_problem))

## Usage

Say your `Widget` class has a method `do_a_thing` that is sometimes quite expensive to calculate, but returns a value you'd like to include in a web page, as long as the value can be made available in five seconds.  Once calculated, the value is valid for ten minutes, and all renderings of the page can show that same value.

In the controller:

```ruby
promise = SidekiqSmartCache::Promise.new(klass: Widget, method: :do_a_thing, expires_in: 10 * 60)
if promise.ready_within?(5.seconds)
  # Render using the generated thing
  @thing = promise.value
else
  # Render some "try again in a bit" presentation
end
```

If no other workers are currently calculating the value, this will queue up a sidekiq job to call `Widget.do_a_thing`.  If other workers are currently calculating, it will not start another, preventing the thundering herd.

Then it will wait as much as 5 seconds for a value to be returned.

If in the end, value is nil, offer a default or "try again" presentation to the user.

Also supported: passing arguments, calling an instance method on an object in the database, and explicitly naming your cache tag.

```ruby
SidekiqSmartCache::Promise.new(
  object: widget, method: :do_an_instance_thing, args: ['fun', 12],
  expires_in: 10.minutes
)
```

*Note*: Only string return values are supported.  Complex structures, and importantly nil values must be implemented in client code.

## Installation
Add this line to your application's Gemfile:

```ruby
gem 'sidekiq_smart_cache'
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install sidekiq_smart_cache
```

Add an initializer:
```ruby
Rails.configuration.to_prepare do
  SidekiqSmartCache.logger = Rails.logger
  SidekiqSmartCache.redis_pool = Sidekiq.redis_pool
  SidekiqSmartCache.cache_prefix = ENV['RAILS_CACHE_ID']
end
```

## Model mix-in

Let's assume your User class has a active_user_count class method that is expensive to calculate

Declaring `make_class_action_cacheable :active_user_count` will add:

 * `User.active_user_count_without_caching` - always performs the full calculation synchronously, doesn't touch the cache.
 * `User.refresh_active_user_count` - always performs the full calculation synchronously, populating the cache with the new value.
 * `User.active_user_count` (the original name) - will now fetch from the cache, only recalculating if the cache is absent or stale.
 * `User.active_user_count_if_available` will now fetch from the cache but not recalculate, returning nil if the cache is absent or stale.
 * `User.active_user_count_cache_tag` - the cache tag used to store calculated results. Probably not useful to clients.
 * `User.active_user_count_promise` - returns a Promise object

Call `promise.fetch(5.seconds)` to wait up to five seconds for a new value, returning nil on timeout.

Call `promise.fetch!(5.seconds)` to wait up to five seconds for a new value, raising `SidekiqSmartCache::TimeoutError` on timeout.

Use <tt>make_instance_action_cacheable</tt> for the equivalent set of instance methods.
Your models must respond to <tt>to_param</tt> with a unique string suitable for constructing a cache key.
The class must respond to <tt>find</tt> and return an object that responds to the method.

## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
