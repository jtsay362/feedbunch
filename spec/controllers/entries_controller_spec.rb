require 'spec_helper'

describe Api::EntriesController do

  before :each do
    @feed = FactoryGirl.create :feed
    @user = FactoryGirl.create :user
    @user.subscribe @feed.fetch_url
    @entry = FactoryGirl.build :entry, feed_id: @feed.id
    @feed.entries << @entry
    login_user_for_unit @user
  end

  context 'PUT update' do

    it 'assigns the correct entry' do
      put :update, entry: {id: @entry.id, state: 'read'}, format: :json
      assigns(:entry).should eq @entry
    end

    it 'returns success' do
      put :update, entry: {id: @entry.id, state: 'read', update_older: 'false'}, format: :json
      response.should be_success
    end

    it 'returns 404 if the entry does not exist' do
      put :update, entry: {id: 1234567890, state: 'read'}, format: :json
      response.status.should eq 404
    end

    it 'returns 404 if the user is not subscribed to the entries feed' do
      entry2 = FactoryGirl.create :entry
      put :update, entry: {id: entry2.id, state: 'read'}, format: :json
      response.status.should eq 404
    end

    it 'returns 500 if there is a problem changing the entry state' do
      User.any_instance.stub(:change_entries_state).and_raise StandardError.new
      put :update, entry: {id: @entry.id, state: 'read'}, format: :json
      response.status.should eq 500
    end
  end
end