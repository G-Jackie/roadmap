class PlanPolicy < ApplicationPolicy
  attr_reader :user
  attr_reader :plan

  def initialize(user, plan)
    raise Pundit::NotAuthorizedError, "must be logged in" unless user || plan.publicly_visible?
    @user = user
    @plan = plan
  end

  def show?
    @plan.readable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

  def share?
    @plan.readable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

  def export?
    @plan.readable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

  def show_export?
    @plan.readable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

  def update?
    @plan.editable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

  def destroy?
    @plan.editable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

  def status?
    @plan.readable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

  def possible_templates?
    @plan.id.nil?
  end

  def duplicate?
    @plan.editable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end
  
  def visibility?
    @plan.administerable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

  def set_test?
    @plan.administerable_by?(@user.id)&& Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

  def public_export?
    @plan.publicly_visible?
  end

  def answer?
    @plan.readable_by?(@user.id) && Role.find_by(user_id: @user.id, plan_id: @plan.id).active
  end

end
