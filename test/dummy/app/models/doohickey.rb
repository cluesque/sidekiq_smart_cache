class Doohickey < ApplicationRecord
  def self.do_a_thing
    doohickey = create(name: "narf #{count + 1}")
    logger.info "Performing #{doohickey.name}"
    sleep 2.0
    logger.info "Completed thing #{doohickey.name}"
    doohickey.name
  end
  def make_a_thing(arg)
    "#{name} #{arg}"
  end
end
