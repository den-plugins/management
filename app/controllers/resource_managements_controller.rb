class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations
  menu_item :forecasts, :only => :forecasts
  menu_item :users, :only => :users

  before_filter :require_management
  before_filter :get_projects_members, :only => [:index, :allocations, :load_chart]
  before_filter :set_cache_buster
  def set_cache_buster
    response.headers["Cache-Control"] = "no-cache, no-store, max-age=0, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"
  end
  
  helper :sort
  include SortHelper
  
  def index
    @users = User.active.engineers
    @skill_set = User.resource_skills.sort
    @categories = Project.project_categories.sort
  end

  def load_chart
    if params[:chart] != "resource_allocation"
      @users = User.active.engineers
      @skill_set = User.resource_skills.sort
    else
      @categories = Project.project_categories.sort
    end
    render :update do |page|
      page.replace_html "show_#{params[:chart]}".to_sym, :partial => "resource_managements/charts/#{params[:chart]}"
    end
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
  
  def users
    sort_init 'login', 'asc'
    #sort_update %w(login firstname lastname skill location hired_date organization is_engineering)
    sort_update %w(login firstname lastname is_engineering)
    
    if filters = params[:filters]
      # temporarily put in the controller
      c = User.generate_user_mgt_condition(filters)
      
      limit = per_page_option
      @users_count  = User.count(:all, :conditions => c.conditions)
      @user_pages = Paginator.new self, @users_count, limit, params['page']
      @users = User.find :all, :limit => limit, :offset => @user_pages.current.offset, :order => sort_clause,
                                           :conditions => c.conditions
    end
    render :template => 'resource_managements/users.rhtml', :layout => !request.xhr?
  end

  def load_weekly_forecasts
    puts " ---- loading weekly forecasts ----"
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
