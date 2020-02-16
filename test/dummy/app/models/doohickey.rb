class Doohickey < ApplicationRecord
  include SidekiqSmartCache::Model
  TIME_UNIT = 2.second # tests are built around this duration for convenience
  DEFAULT_DURATION = 2 * TIME_UNIT

  def median_thromboid_density(arg_one, arg_two, complexity_factor)
    sleep complexity_factor
    "#{name} #{arg_one} #{arg_two}"
  end
  make_instance_action_cacheable :median_thromboid_density, expires_in: 1.minute

  def self.take_a_moment(duration = DEFAULT_DURATION, value = 'done')
    sleep duration
    value
  end

  def self.do_a_thing(duration = DEFAULT_DURATION)
    doohickey = create(name: "narf #{count + 1}")
    logger.info "Performing #{doohickey.name}"
    sleep duration
    logger.info "Completed thing #{doohickey.name}"
    doohickey.name
  end

  def make_a_thing(arg)
    "#{name} #{arg}"
  end
end
