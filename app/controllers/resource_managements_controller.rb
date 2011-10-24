class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations

  before_filter :require_management
  helper :resource_costs
  
  def index
  end
  
  def allocations
    @projects = Project.active.find(:all, :order => 'name ASC')
    @members = []
    @projects.each do |project|
      @members += project.members.project_team
    end
  end
  
  private
  def require_management
    return unless require_login
    if !User.current.allowed_to?(:manage_resources, nil, :global => true)
      render_403
      return false
    end
    true
  end
end
