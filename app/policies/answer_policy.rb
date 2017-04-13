class AnswerPolicy < ApplicationPolicy
  attr_reader :user
  attr_reader :answer

  def initialize(user, answer)
    raise Pundit::NotAuthorizedError, "must be logged in" unless user
    @user = user
    @answer = answer
  end

  def update?
    # is the plan editable by the user
    @answer.plan.editable_by?(@user.id)
  end

end