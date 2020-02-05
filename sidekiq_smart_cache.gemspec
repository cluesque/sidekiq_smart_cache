$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "sidekiq_smart_cache/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "sidekiq_smart_cache"
  s.version     = SidekiqSmartCache::VERSION
  s.authors     = ["Bill Kirtley"]
  s.email       = ["bill.kirtley@gmail.com"]
  s.homepage    = "TODO"
  s.summary     = "TODO: Summary of SidekiqSmartCache."
  s.description = "TODO: Description of SidekiqSmartCache."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rails", "~> 5.1.6", ">= 5.1.6.2"

  s.add_development_dependency "sqlite3"
end
