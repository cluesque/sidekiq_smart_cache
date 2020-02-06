class Doohickey < ApplicationRecord
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
