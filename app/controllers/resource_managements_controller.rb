class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations
  menu_item :forecasts, :only => :forecasts
  menu_item :users, :only => :users
  menu_item :utilization, :only => :utilization

  helper :users, :custom_fields

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
    get_forecast_list
    render :template => 'resource_managements/forecasts.rhtml', :layout => !request.xhr?
  end
  
  def users
    sort_init 'login', 'asc'
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
  
  def utilization
  end
  
  def add_user
    @auth_sources = AuthSource.find(:all)
    if request.get?
      @user = User.new(:language => Setting.default_language)
      render :template => 'resource_managements/users/add_user.rhtml', :layout => !request.xhr?
    else
      @user = User.new(params[:user])
      @user.admin = params[:user][:admin] || false
      @user.login = params[:user][:login]
      @user.password, @user.password_confirmation = params[:password], params[:password_confirmation] unless @user.auth_source_id
      if @user.save
        resource = Resource.new
        resource.user = @user
        if resource.save
          @user.resource = resource
        end
        Mailer.deliver_account_information(@user, params[:password]) if params[:send_information]
        flash[:notice] = l(:notice_successful_create)
        redirect_to(url_for(:action => 'users', :filters => params[:filters]))
      else
        render :template => 'resource_managements/users/add_user.rhtml', :layout => !request.xhr?
      end
    end
  end

  def edit_user
    @user = User.find(params[:id])
    @auth_sources = AuthSource.find(:all)
    @roles = Role.find_all_givable
    @projects = Project.active.find(:all, :order => 'lft')
    @membership ||= Member.new
    @memberships = @user.memberships
    @skills = Skill.find(:all)
    if request.get?
      render :template => 'resource_managements/users/edit_user.rhtml', :layout => !request.xhr?
    elsif request.post?
      @user.admin = params[:user][:admin] if params[:user][:admin]
      @user.login = params[:user][:login] if params[:user][:login]
      @user.password, @user.password_confirmation = params[:password], params[:password_confirmation] unless params[:password].nil? or params[:password].empty? or @user.auth_source_id
      @user.attributes = params[:user]
      # Was the account actived ? (do it before User#save clears the change)
      was_activated = (@user.status_change == [User::STATUS_REGISTERED, User::STATUS_ACTIVE])
      if @user.save
        Mailer.deliver_account_activated(@user) if was_activated
        flash[:notice] = l(:notice_successful_update)
        # Give a string to redirect_to otherwise it would use status param as the response code
        redirect_to(url_for(:action => 'users', :filters => params[:filters]))
      else
        render :template => 'resource_managements/users/edit_user.rhtml', :layout => !request.xhr?
      end
    end
  end

  def edit_membership
    @user = User.find(params[:id])
    if request.post? 
      if params[:projects]
        new_projects = params[:projects].collect{|p| Member.new(:project_id => p.to_i, :role_id => params[:membership][:role_id].to_i)} 
        @user.members << new_projects
      end   
      if params[:membership_id]
        @membership = Member.find(params[:membership_id])
        @membership.attributes = params[:membership]
        @membership.save
      end
    end
    redirect_to :action => 'edit_user', :id => @user, :tab => 'memberships'
  end
  
  def destroy_membership
    @user = User.find(params[:id])
    Member.find(params[:membership_id]).destroy if request.post?
    redirect_to :action => 'edit_user', :id => @user, :tab => 'memberships'
  end

  def load_weekly_forecasts
    get_forecast_list
    @forecasts = {}
    @summary = {}
    acctg = params[:acctg].to_s.blank? ? "Billable" : params[:acctg]
    
    if params[:reload]
      delay_job
      render :update do |page|
        page.insert_html :after, :project_acctg_form, "<div class='flash notice'>Process enqueued.</div>"
      end
    else
      if FileTest.exists?("#{RAILS_ROOT}/config/rm_forecasts.yml")
        if file = YAML.load(File.open("#{RAILS_ROOT}/config/rm_forecasts.yml"))
          if mgt = file[acctg]
            @forecasts = mgt["forecasts"]
            @summary = mgt["summary"]
            @updated_at = mgt["updated_at"]
            render :update do |page|
              page.replace_html :weekly_forecasts_panel, :partial => 'resource_managements/forecasts/weeks',
                        :locals => {:total_res_available => params[:total_res_available].to_i }
            end
          else
            delay_job
            render_empty_weeks
          end
        else
          delay_job
          render_empty_weeks
        end
      else
        delay_job
        render_empty_weeks
      end
    end
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
    @projects.each{|project| @members += project.members.all(:include => [:user],
                             :conditions => ["proj_team = true"],
                             :order => "users.firstname ASC, users.lastname ASC").select {|m| !m.user.is_resigned}}
  end
  
  def get_forecast_list
    limit = per_page_option
    dev_projects = Project.development.find(:all, :include => [:accounting])
    acctg = params[:acctg].to_s.blank? ? "Billable" : params[:acctg]
    if acctg.eql?('Both')
      @projects = dev_projects.collect {|p| p.id if (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable'))}.compact.uniq
    else
      @projects = dev_projects.collect {|p| p.id if (p.accounting_type.eql?( acctg))}.compact.uniq
    end

    if @projects.empty?
      @resources = []
    else
      @resources_no_limit = User.active.engineers.find(:all, :order => "firstname ASC, lastname ASC", :include => [:projects, :members]).select do |resource|
        resource unless resource.memberships.select {|m| m.project.active? and @projects.include?(m.project_id) }.empty?
      end
      @resource_count = @resources_no_limit.count
      @resource_pages = Paginator.new self, @resource_count, limit, params['page']
      offset = @resource_pages.current.offset
      @resources = []
      (offset ... (offset + limit)).each do |i|
        break if @resources_no_limit[i].nil?
        @resources << @resources_no_limit[i]
      end
    end
    @skill_set = User.resource_skills
  
    #@resources_no_limit = User.tmp_resources_no_limit
    #@resources = User.tmp_resources
    #@projects = Project.tmp_projects
    #@skill_set = User.tmp_skillset
  end
  
  def delay_job
    acctg = params[:acctg].to_s.blank? ? "Billable" : params[:acctg]
    resources_no_limit = @resources_no_limit.collect {|r| r.id }
    handler = ForecastJob.new(acctg, resources_no_limit, @skill_set, @projects, params[:total_res_available])
    Delayed::Job.enqueue handler unless Delayed::Job.find_by_handler(handler.to_yaml)
  end
  
  def render_empty_weeks
    render :update do |page|
      page.replace_html :weekly_forecasts_panel, :partial => 'resource_managements/forecasts/empty_weeks',
                :locals => {:total_res_available => params[:total_res_available].to_i }
      page.hide :icon_reload_forecasts
      page.hide :updated_at_text
    end
  end
end
