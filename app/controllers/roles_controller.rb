class RolesController < ApplicationController
  respond_to :html
  after_action :verify_authorized

  def create
    registered = true
    @role = Role.new(role_params)
    authorize @role
    
    access_level = params[:role][:access_level].to_i
    set_access_level(access_level)
    message = ''
    if params[:user].present?
      if @role.plan.owner.present? && @role.plan.owner.email == params[:user]
        flash[:notice] = _('Cannot share plan with %{email} since that email matches with the owner of the plan.') % {email: params[:user]}
      else
        user = User.where_case_insensitive('email',params[:user]).first
        if Role.find_by(plan: @role.plan, user: user) # role already exists
          flash[:notice] = _('Plan is already shared with %{email}.') % {email: params[:user]}
        else
          if user.nil?
            registered = false
            User.invite!(email: params[:user])
            message = _('Invitation to %{email} issued successfully. \n') % {email: params[:user]}
            user = User.find_by(email: params[:user])
          end
          message += _('Plan shared with %{email}.') % {email: user.email}
          @role.user = user
          if @role.save
            if registered then UserMailer.sharing_notification(@role, current_user).deliver_now end
            flash[:notice] = message
          else
            flash[:alert] = failed_create_error(@role, _('role'))
          end
        end
      end
    else
      flash[:notice] = _('Please enter an email address')
    end
    redirect_to controller: 'plans', action: 'share', id: @role.plan.id
  end


  def update
    @role = Role.find(params[:id])
    authorize @role
    access_level = params[:role][:access_level].to_i
    set_access_level(access_level)
    if @role.update_attributes(role_params)
      UserMailer.permissions_change_notification(@role, current_user).deliver_now
      render json: {code: 1, msg: "Successfully changed the permissions for #{@role.user.email}. They have been notified via email."}
    else
      render json: {code: 0, msg: flash[:alert]}
    end
  end

  def destroy
    @role = Role.find(params[:id])
    authorize @role
    user = @role.user
    plan = @role.plan
    @role.destroy
    flash[:notice] = _('Access removed')
    UserMailer.project_access_removed_notification(user, plan, current_user).deliver_now
    redirect_to controller: 'plans', action: 'share', id: @role.plan.id
  end
    
  # This function makes user's role on a plan inactive - i.e. "removes" this from their plans
  def deactivate
    role = Role.find(params[:id])
    authorize role
    role.active = false
    # if creator, remove from public plans list
    if role.creator? && role.plan.publicly_visible?
      role.plan.visibility = Plan.visibilities[:privately_visible]
      role.plan.save
    end
    if role.save
      flash[:notice] = _('Plan removed')
    end
    redirect_to(plans_path)
  end

  private

  def role_params
    params.require(:role).permit(:plan_id)
  end

  def set_access_level(access_level)
    if access_level >= 1
      @role.commenter = true
    else
      @role.commenter = false
    end
    if access_level >= 2
      @role.editor = true
    else
      @role.editor = false
    end
    if access_level >= 3
      @role.administrator = true
    else
      @role.administrator = false
    end
  end

end
