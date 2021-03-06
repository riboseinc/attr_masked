require "database_cleaner"

RSpec.configure do |config|
  config.before(:suite) do
    unless WITHOUT_ACTIVE_RECORD
      require "database_cleaner-active_record"
      DatabaseCleaner[:active_record].strategy = :truncation
    end

    # Since models are defined dynamically in specs, Database Cleaner is unable
    # to list them and to determine collection names to be cleaned.
    # Therefore, they are specified explicitly here.
    unless WITHOUT_MONGOID
      require "database_cleaner-mongoid"
      DatabaseCleaner[:mongoid].strategy = :deletion, { only: %w[users] }
    end

    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
