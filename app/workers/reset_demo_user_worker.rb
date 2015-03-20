##
# Background worker to create the demo user (if it doesn't exist yet) and reset its configuration, folders and
# subscribed feeds.
#
# The credentials for the demo user are:
# - email: demo@feedbunch.com
# - password: feedbunch-demo
#
# This is a Sidekiq worker

class ResetDemoUserWorker
  include Sidekiq::Worker
  include Sidetiq::Schedulable

  # This worker runs periodically. Do not retry.
  sidekiq_options retry: false, queue: :maintenance
  # Run every hour.
  recurrence do
    hourly
  end

  DEMO_EMAIL = 'demo@feedbunch.com'
  DEMO_PASSWORD = 'feedbunch-demo'

  ##
  # Create the demo user if it still doesn't exist. Reset its configuration, folders and subscribed feeds.

  def perform
    Rails.logger.debug 'Resetting demo user'

    unless User.exists? email: DEMO_EMAIL
      demo_user = User.new email: DEMO_EMAIL,
                           password: DEMO_PASSWORD,
                           confirmed_at: Time.zone.now
      Rails.logger.debug 'Demo user does not exist, creating it'
      demo_user.save!
    end
  end
end