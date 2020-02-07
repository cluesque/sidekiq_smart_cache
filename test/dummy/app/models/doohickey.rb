class Doohickey < ApplicationRecord
  include SidekiqSmartCache::Model
  def median_thromboid_density(arg_one, arg_two, complexity_factor)
    sleep complexity_factor
    "#{name} #{arg_one} #{arg_two}"
  end
  make_instance_action_cacheable :median_thromboid_density, expires_in: 1.minute

  def self.do_a_thing(duration = 2.0)
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
