class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations

  before_filter :require_management
  helper :resource_costs
  
  def index
  end
  
  def allocations
    @projects = Project.active.find(:all, :order => 'name ASC').select {|project| project.project_type.eql?('Development')}
    @members = []
    @projects.each{|project| @members += project.members.select {|m| m.user.is_engineering and !m.user.is_resigned}}
  end
  
  private
  def require_management
    return unless require_login
    if !User.current.allowed_to?(:manage_resources, nil, :global => true) && !User.current.admin?
      render_403
      return false
    end
    true
  end
end
