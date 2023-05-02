# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "sidekiq"
require 'sidekiq/testing'
require 'sidekiq/launcher'


puts "Testing against Sidekiq #{Sidekiq::VERSION}"

require File.expand_path("../../test/dummy/config/environment.rb", __FILE__)
ActiveRecord::Migrator.migrations_paths = [File.expand_path("../../test/dummy/db/migrate", __FILE__)]
require "rails/test_help"

# Filter out Minitest backtrace while allowing backtrace from other libraries
# to be shown.
Minitest.backtrace_filter = Minitest::BacktraceFilter.new

Rails::TestUnitReporter.executable = 'bin/test'

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_path=)
  ActiveSupport::TestCase.fixture_path = File.expand_path("../fixtures", __FILE__)
  ActionDispatch::IntegrationTest.fixture_path = ActiveSupport::TestCase.fixture_path
  ActiveSupport::TestCase.file_fixture_path = ActiveSupport::TestCase.fixture_path + "/files"
  ActiveSupport::TestCase.fixtures :all
end

class ActiveSupport::TestCase
  # This extension prints to the log before each test.  Makes it easier to find the test you're looking for
  # when looking through a long test log.
  setup :log_test

  private

  def log_test
    if Rails::logger
      # When I run tests in rake or autotest I see the same log message multiple times per test for some reason.
      # This guard prevents that.
      unless @already_logged_this_test
        Rails::logger.info "\n\nStarting #{name}\n#{'-' * (9 + name.length)}\n"
      end
      @already_logged_this_test = true
    end
  end
end
