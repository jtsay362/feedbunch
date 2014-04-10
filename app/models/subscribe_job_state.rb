##
# SubscribeJobState model. Each instance of this class represents an ocurrence of a user trying to
# subscribe to a feed.
#
# Each SubscribeJobState belongs to a single user, and each user can have many SubscribeJobStates
# (one-to-many relationship).
#
# The SubscribeJobState model has the following fields:
# - state: mandatory text that indicates the current state of the import process. Supported values are
# "RUNNING" (the default), "SUCCESS" and "ERROR".
# - fetch_url: URL of the feed, entered by the user.
# - feed_id: id of the subscribed feed; only different from nil if the state is SUCCESS.

class SubscribeJobState < ActiveRecord::Base
  # Class constants for the possible states
  RUNNING = 'RUNNING'
  ERROR = 'ERROR'
  SUCCESS = 'SUCCESS'

  belongs_to :user
  validates :user_id, presence: true

  belongs_to :feed
  validate :feed_id_present_only_if_job_successful

  validates :state, presence: true, inclusion: {in: [RUNNING, ERROR, SUCCESS]}
  validates :fetch_url, presence: true

  before_validation :default_values

  private

  ##
  # By default, a SubscribeJobState is in the "RUNNING" state unless specified otherwise.

  def default_values
    self.state = RUNNING if self.state.blank?
  end

  ##
  # Validate that the feed_id attribute is present if and only if the job state is "SUCCESS"

  def feed_id_present_only_if_job_successful
    if state == SUCCESS && feed_id.blank?
      errors.add :feed_id, "can't be blank if the job state is SUCCESS"
    elsif state != SUCCESS && feed_id.present?
      errors.add :feed_id, "must be blank if the job state is different from SUCCESS"
    end
  end
end
