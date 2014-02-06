require 'spec_helper'

describe UpdateFeedJob do

  before :each do
    @feed = FactoryGirl.create :feed
    FeedClient.stub :fetch
  end

  it 'updates feed when the job runs' do
    FeedClient.should_receive(:fetch).with @feed, anything

    UpdateFeedJob.perform @feed.id
  end

  it 'recalculates unread entries count in feed' do
    # user is subscribed to @feed with 1 entry
    user = FactoryGirl.create :user

    entry = FactoryGirl.build :entry, feed_id: @feed.id
    @feed.entries << entry

    user.subscribe @feed.fetch_url

    # @feed has an incorrect unread entry count of 10 for user
    feed_subscription = FeedSubscription.where(user_id: user.id, feed_id: @feed.id).first
    feed_subscription.update unread_entries: 10

    UpdateFeedJob.perform @feed.id

    # Unread count should be corrected
    user.feed_unread_count(@feed).should eq 1
  end

  it 'unschedules updates if the feed has been deleted when the job runs' do
    @feed.destroy
    Resque.should_receive(:remove_schedule).with "update_feed_#{@feed.id}"
    FeedClient.should_not_receive :fetch

    UpdateFeedJob.perform @feed.id
  end

  it 'does not update feed if it has been deleted' do
    FeedClient.should_not_receive :fetch
    @feed.destroy

    UpdateFeedJob.perform @feed.id
  end

  context 'adaptative schedule' do

    it 'updates the last_fetched timestamp of the feed when successful' do
      date = DateTime.new 2000, 1, 1
      DateTime.stub(:now).and_return date

      @feed.last_fetched.should be_nil
      UpdateFeedJob.perform @feed.id
      @feed.reload.last_fetched.should eq date
    end

    it 'decrements a 10% the fetch interval if new entries are fetched' do
      FeedClient.stub(:fetch) do
        entry = FactoryGirl.build :entry, feed_id: @feed.id
        @feed.entries << entry
      end

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '3240s'
        config[:every][1].should eq ({first_in: 3240})
      end

      @feed.reload.fetch_interval_secs.should eq 3600
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 3240
    end

    it 'increments a 10% the fetch interval if no new entries are fetched' do
      FeedClient.stub(:fetch)

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '3960s'
        config[:every][1].should eq ({first_in: 3960})
      end

      @feed.reload.fetch_interval_secs.should eq 3600
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 3960
    end

    it 'does not set a fetch interval smaller than the configured minimum' do
      FeedClient.stub(:fetch) do
        entry = FactoryGirl.build :entry, feed_id: @feed.id
        @feed.entries << entry
      end

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '900s'
        config[:every][1].should eq ({first_in: 900.seconds})
      end

      @feed.update fetch_interval_secs: 15.minutes
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 15.minutes
    end

    it 'does not set a fetch interval greater than the configured maximum' do
      FeedClient.stub(:fetch)

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '86400s'
        config[:every][1].should eq ({first_in: 24.hours})
      end

      @feed.update fetch_interval_secs: 24.hours
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 24.hours
    end

  end

  context 'error handling' do

    it 'increments the fetch interval if the feed server returns an HTTP error status' do
      FeedClient.stub(:fetch).and_raise RestClient::Exception.new

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '3960s'
        config[:every][1].should eq ({first_in: 3960})
      end

      @feed.fetch_interval_secs.should eq 3600
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 3960
    end

    it 'increments the fetch interval if the feed server FQDN cannot be resolved' do
      FeedClient.stub(:fetch).and_raise SocketError.new('getaddrinfo: Name or service not known')

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '3960s'
        config[:every][1].should eq ({first_in: 3960})
      end

      @feed.fetch_interval_secs.should eq 3600
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 3960
    end

    it 'increments the fetch interval if the feed server connection times out' do
      FeedClient.stub(:fetch).and_raise Errno::ETIMEDOUT.new('Connection timed out')

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '3960s'
        config[:every][1].should eq ({first_in: 3960})
      end

      @feed.fetch_interval_secs.should eq 3600
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 3960
    end

    it 'increments the fetch interval if the feed server response is empty' do
      FeedClient.stub(:fetch).and_raise EmptyResponseError.new

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '3960s'
        config[:every][1].should eq ({first_in: 3960})
      end

      @feed.fetch_interval_secs.should eq 3600
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 3960
    end

    it 'increments the fetch interval if there is a problem trying to do a feed autodiscovery' do
      FeedClient.stub(:fetch).and_raise FeedAutodiscoveryError.new

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '3960s'
        config[:every][1].should eq ({first_in: 3960})
      end

      @feed.fetch_interval_secs.should eq 3600
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 3960
    end

    it 'increments the fetch interval if there is a problem trying to fetch a valid feed xml' do
      FeedClient.stub(:fetch).and_raise FeedFetchError.new

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '3960s'
        config[:every][1].should eq ({first_in: 3960})
      end

      @feed.fetch_interval_secs.should eq 3600
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 3960
    end

    it 'increments the fetch interval if there is a problem trying to parse the xml response' do
      FeedClient.stub(:fetch).and_raise FeedParseError.new

      Resque.should_receive :set_schedule do |name, config|
        name.should eq "update_feed_#{@feed.id}"
        config[:class].should eq 'UpdateFeedJob'
        config[:persist].should be_true
        config[:args].should eq @feed.id
        config[:every][0].should eq '3960s'
        config[:every][1].should eq ({first_in: 3960})
      end

      @feed.fetch_interval_secs.should eq 3600
      UpdateFeedJob.perform @feed.id
      @feed.reload.fetch_interval_secs.should eq 3960
    end
  end

  context 'failing feed' do

    it 'sets failing_since to the current date&time the first time an update fails' do
      FeedClient.stub(:fetch).and_raise RestClient::Exception.new
      date = DateTime.new 2000, 1, 1
      DateTime.stub(:now).and_return date

      @feed.failing_since.should be_nil
      UpdateFeedJob.perform @feed.id
      @feed.reload.failing_since.should eq date
    end

    it 'sets failing_since to nil when an update runs successfully' do
      FeedClient.stub(:fetch)
      date = DateTime.new 2000, 1, 1
      @feed.update failing_since: date

      @feed.failing_since.should eq date
      UpdateFeedJob.perform @feed.id
      @feed.reload.failing_since.should be_nil
    end

    it 'does not change failing_since the second and sucesive times an update fails successively' do
      FeedClient.stub(:fetch).and_raise RestClient::Exception.new
      date1 = DateTime.new 2000, 1, 1
      DateTime.stub(:now).and_return date1
      date2 = DateTime.new 1990, 1, 1
      @feed.update failing_since: date2

      @feed.failing_since.should eq date2
      UpdateFeedJob.perform @feed.id
      @feed.reload.failing_since.should eq date2
    end

    it 'marks feed as unavailable when it has been failing longer than a week' do
      FeedClient.stub(:fetch).and_raise RestClient::Exception.new
      date = DateTime.new 2000, 1, 1
      DateTime.stub(:now).and_return date
      @feed.update failing_since: date - (1.week + 1.day)

      @feed.available.should be_true
      UpdateFeedJob.perform @feed.id
      @feed.reload.available.should be_false
    end

    it 'unschedules updates for a feed when it has been failing longer than a week' do
      FeedClient.stub(:fetch).and_raise RestClient::Exception.new
      date = DateTime.new 2000, 1, 1
      DateTime.stub(:now).and_return date
      @feed.update failing_since: date - (1.week + 1.day)

      Resque.should_receive(:remove_schedule).with "update_feed_#{@feed.id}"

      UpdateFeedJob.perform @feed.id
    end

    it 'does not mark feed as unavailable when it has been failing a week but the next update is successful' do
      FeedClient.stub :fetch
      date = DateTime.new 2000, 1, 1
      DateTime.stub(:now).and_return date
      @feed.update failing_since: date - (1.week + 1.day)

      @feed.available.should be_true
      UpdateFeedJob.perform @feed.id
      @feed.reload.available.should be_true
    end

    it 'does not mark feed as unavailable when it updates successfully' do
      FeedClient.stub :fetch
      @feed.update failing_since: nil

      @feed.available.should be_true
      UpdateFeedJob.perform @feed.id
      @feed.reload.available.should be_true
    end
  end

end