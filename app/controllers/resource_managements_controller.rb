class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations
  menu_item :forecasts, :only => :forecasts

  before_filter :require_management
  before_filter :get_projects_members, :only => [:index, :allocations]
  
  def index
    @users = User.active.engineers
    @skill_set = User.resource_skills.sort
    @categories = Project.project_categories.sort
  end
  
  def allocations
    @categories = Project.project_categories
  end
  
  def forecasts
    limit = per_page_option
    dev_projects = Project.development.find(:all, :include => [:accounting])
    if params[:acctg] && params[:acctg].eql?('Both')
      @projects = dev_projects.collect {|p| p.id if (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable'))}.compact.uniq
    else
      @projects = dev_projects.collect {|p| p.id if (p.accounting_type.eql?( params[:acctg] || 'Billable'))}.compact.uniq
    end

    if @projects.empty?
      @resources = []
    else
      #development = "and projects.id IN (#{@projects.join(', ')})"
      #active_project = "select id, status from projects where projects.id = members.project_id and projects.status = 1 #{development}"
      #statement = "exists (select user_id, project_id from members where members.user_id = users.id and exists (#{active_project}))"
      #@resources_no_limit = User.active.engineers.find(:all, :select => "users.firstname, users.lastname, users.id",
      #                                                          :include => [:projects, :members],
      #                                                          :conditions => statement,
      #                                                          :order => "firstname ASC, lastname ASC")
      
      @resources_no_limit = User.active.engineers.find(:all, :order => "firstname ASC, lastname ASC", :include => [:projects, :members]).select do |resource|
        resource unless resource.memberships.select {|m| m.project.active? and @projects.include?(m.project_id) }.empty?
      end
      @resource_count = @resources_no_limit.count
      @resource_pages = Paginator.new self, @resource_count, limit, params['page']
      offset = @resource_pages.current.offset
      @resources = []
      ## modified offset, limit approach through array rather than query
      (offset ... (offset + limit)).each do |i|
        break if @resources_no_limit[i].nil?
        @resources << @resources_no_limit[i]
      end
    end
    @skill_set = User.resource_skills
    User.tmp_resources_no_limit = @resources_no_limit
    User.tmp_resources = @resources
    Project.tmp_projects = @projects
    User.tmp_skillset = @skill_set
    render :template => 'resource_managements/forecasts.rhtml', :layout => !request.xhr?
  end

  def load_weekly_forecasts
    @resources_no_limit = User.tmp_resources_no_limit
    @resources = User.tmp_resources
    @projects = Project.tmp_projects
    @skill_set = User.tmp_skillset
    render :partial => 'resource_managements/forecasts/weeks', 
         :locals => {:total_res_available => params[:total_res_available].to_i}
  end
  
  private
  def require_management
    return unless require_login
    unless User.current.allowed_to?(:manage_resources, nil, :global => true) || User.current.admin?
      render_403
      return false
    end
    true
  end
  
  def get_projects_members
    @projects = Project.active.development.find(:all, :include => [:accounting])
    @members = []
    @projects.each{|project| @members += project.members.all(:include => [:user], :order => "users.firstname ASC, users.lastname ASC").select {|m| !m.user.is_resigned}}
  end
end
