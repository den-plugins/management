class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations
  menu_item :forecasts, :only => :forecasts

  before_filter :require_management
  helper :resource_costs
  
  def index
  end
  
  def allocations
    @projects = Project.active.find(:all, :order => 'name ASC').select {|project| project.project_type.eql?('Development')}
    @members = []
    @projects.each{|project| @members += project.members.select {|m| m.user.is_engineering and !m.user.is_resigned}}
  end
  
  def forecasts
    limit = per_page_option
    active_project = "select id, status from projects where projects.id = members.project_id and projects.status = 1"
    statement = "exists (select user_id, project_id from members where members.user_id = users.id and exists (#{active_project}))"
    @resource_count = User.active.engineers.count(:all, :include => [:projects, :members], :conditions => statement)
    @resource_pages = Paginator.new self, @resource_count, limit, params['page']
    @resources = User.active.engineers.find :all,
                                        :include => [:projects, :members],
                                        :conditions => statement,
                                        :limit => limit,
                                        :offset => @resource_pages.current.offset,
                                        :order => "firstname ASC, lastname ASC"
      render :template => 'resource_managements/forecasts.rhtml', :layout => !request.xhr?
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
