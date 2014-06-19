##
# Customized version of Devise::InvitationsController.
# It has been customized to better work with AJAX requests.

class Devise::FriendInvitationsController < Devise::InvitationsController

  respond_to :json, only: [:create]

  prepend_before_filter :authenticate_inviter!, :only => [:create]
  prepend_before_filter :has_invitations_left?, :only => [:create]
  helper_method :after_sign_in_path_for

  ##
  # Send an invitation email to the passed email address.

  def create
    invited_email = friend_invitation_params[:email]

    # TODO after beta stage remove this to allow anyone to invite friends
    if !current_inviter.admin
      Rails.logger.warn "User #{current_inviter.id} - #{current_inviter.email} tried to send invitation to #{invited_email} without being an admin"
      head status: 403
      return
    end

    # Check if user already exists
    if User.exists? email: invited_email
      Rails.logger.warn "User #{current_inviter.id} - #{current_inviter.email} tried to send invitation to #{invited_email} but a user with that email already exists"
      head status: 409
      return
    end

    # Create record for the invited user
    @invited_user = invite_user invited_email
    # If the created user is invalid, this will raise an error
    @invited_user.save!
    Rails.logger.info "User #{current_inviter.id} - #{current_inviter.email} sent invitation to join Feedbunch to user #{@invited_user.id} - #{@invited_user.email}"
    head status: :ok
  rescue => e
    handle_error e
  end

  protected

  ##
  # Create a user invitation.

  # This creates a User instance in unconfirmed state, and sends an invitation email.
  # The new user initially has the same locale and timezone as the inviter, and his username will default to his
  # email address. All these values can be changed after accepting the invitation.
  #
  # Receives as argument the email of the invited user. The invitation will be sent to this email address.

  def invite_user(email)
    invitation_params = {email: email,
                         name: email,
                         locale: current_inviter.locale,
                         timezone: current_inviter.timezone}
    User.invite! invitation_params, current_inviter
  end

  ##
  # Return the user who is sending the invitation.

  def current_inviter
    authenticate_inviter!
  end

  ##
  # Validate that the user sending the invitation actually has invitations left.
  # If he doesn't, an HTTP 400 is returned and the response chain is aborted.

  def has_invitations_left?
    unless current_inviter.nil? || current_inviter.has_invitations_left?
      Rails.logger.warn "User #{current_inviter.id} - #{current_inviter.email} tried to send an invitation, but has no invitations left"
      head status: 400
      return
    end
  end

  ##
  # Filter the accepted HTTP params, according to Rails 4 Strong Parameters feature.

  def friend_invitation_params
    params.require(:user).permit(:email)
  end
end