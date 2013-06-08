require 'resque'

# Resque-scheduler additions to resque-web
require 'resque_scheduler'
require 'resque_scheduler/server'

rails_root = Rails.root || File.dirname(__FILE__) + '/../..'
rails_env = Rails.env || 'development'

resque_config = YAML.load_file(rails_root.to_s + '/config/resque.yml')
Resque.redis = resque_config[rails_env]

# If you want to be able to dynamically change the schedule,
# uncomment this line.  A dynamic schedule can be updated via the
# Resque::Scheduler.set_schedule (and remove_schedule) methods.
# When dynamic is set to true, the scheduler process looks for
# schedule changes and applies them on the fly.
# Note: This feature is only available in >=2.0.0.
Resque::Scheduler.dynamic = true

# The schedule doesn't need to be stored in a YAML, it just needs to
# be a hash.  YAML is usually the easiest.
#Resque.schedule = YAML.load_file(rails_root.to_s + '/config/job_schedule.yml')

Resque.before_fork do |job|
  # Reconnect to the DB before running each job. Otherwise we get errors if the DB
  # is restarted after starting Resque.
  # Absolutely necessary on Heroku, otherwise we get a "PG::Error: SSL SYSCALL error: EOF detected" exception
  ActiveRecord::Base.establish_connection
end