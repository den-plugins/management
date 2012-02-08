class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations
  menu_item :forecasts, :only => :forecasts
  menu_item :users, :only => :users
  menu_item :utilization, :only => :utilization

  helper :users, :custom_fields, :scrums, :ticker

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
    sort_init "lastname"
    sort_update %w(lastname)
    get_forecast_list(sort_clause)

    if params[:sort]
      render :update do |page|
        page.replace_html :mgt_forecast_list, :partial => "resource_managements/forecasts/list"
      end
    else
      render :template => 'resource_managements/forecasts.rhtml', :layout => !request.xhr?
    end
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
    @selected_users = []
    utilization_filters
    respond_to do |format|
      format.html { render :layout => !request.xhr? }
    end
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
    clause = session['resource_managements_forecasts_sort'].gsub(/:/, " ")
    get_forecast_list(clause)

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
  
  def get_forecast_list(order)
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
      @resources_no_limit = User.active.engineers.find(:all, :order => order, :include => [:projects, :members]).select do |resource|
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

# Retrieves the date range based on predefined ranges or specific from/to param dates
  def retrieve_date_range(period_type,period)
    @free_period = false
    @from, @to = nil, nil

    if period_type == '1' || (period_type.nil? && !period_type.nil?)
      case period.to_s
      when 'today'
        @from = @to = Date.today
      when 'yesterday'
        @from = @to = Date.today - 1
      when 'current_week'
        @from = Date.today - (Date.today.cwday - 1)%7
        @to = @from + 6
      when 'last_week'
        @from = Date.today - 7 - (Date.today.cwday - 1)%7
        @to = @from + 6
      when '7_days'
        @from = Date.today - 7
        @to = Date.today
      when 'current_month'
         current_month
      when 'last_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1) << 1
        @to = (@from >> 1) - 1
      when '30_days'
        @from = Date.today - 30
        @to = Date.today
      when 'current_year'
        @from = Date.civil(Date.today.year, 1, 1)
        @to = Date.civil(Date.today.year, 12, 31)
      end
    elsif period_type == '2' || (period_type.nil? && (!params[:from].nil? || !params[:to].nil?))
      begin; @from = params[:from].to_s.to_date unless params[:from].blank?; rescue; end
      begin; @to = params[:to].to_s.to_date unless params[:to].blank?; rescue; end
      begin; @from = params[:leaves_from].to_s.to_date unless params[:leaves_from].blank?; rescue; end
      begin; @to = params[:leaves_to].to_s.to_date unless params[:leaves_to].blank?; rescue; end
      @free_period = true
    else
      # default
      current_month
    end
    
    @from, @to = @to, @from if @from && @to && @from > @to
    @from ||= (TimeEntry.minimum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_time_entries)) || Date.today) - 1
    @to   ||= (TimeEntry.maximum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_time_entries)) || Date.today)
  end

  def current_month
    @from = Date.civil(Date.today.year, Date.today.month, 1)
    @to = (@from >> 1) - 1
  end

  def utilization_filters
    @billing_model = CustomField.find_by_name('Billing Model')

  	if @billing_model
	  	@billing_model_values = [["All", "0"]]
	  	@billing_model.possible_values.each do |v|
	  		@billing_model_values << v
	  	end
	  end

   	@project_type = CustomField.find_by_name('Project Type')

  	if @project_type
	  	@project_type_values = [["All", "0"]]
	  	@project_type.possible_values.each do |line|
	  		@project_type_values << line
	  	end
	  end	  

    retrieve_date_range(params[:period_type], params[:period])
    @columns = (params[:columns] && %w(year month week day).include?(params[:columns])) ? params[:columns] : 'month'
    @query = (params[:query].blank?)? "user" : params[:query]
    @disable_acctype_options = (@query == "user")? true : false
    @eng_only, eng_only = (params[:eng_only] == "1" || params[:right].blank? )? [true, "is_engineering = true"] : [false, nil] 
    @for_acctg = (params[:for_acctg] == "1" )? true : false
    @show_only = (params[:show_only].blank?)? "both" : params[:show_only]
    @tall ||= []

    @selected_acctype = ((params[:acctype].blank?)? "" : params[:acctype]).to_i
    @acctype_options = [["All", ""]]
    Enumeration.accounting_types.each do |at|
      @acctype_options << [at.name, at.id]
    end
    
    user_select = "id, firstname, lastname, status"
    user_order = "firstname asc, lastname asc"
    project_select = "id, name"
    project_order = "name asc"
    eng_only = "is_engineering = true"
    
    @billing = params[:billing_model]
    @project_billing_ids = []
    billings = CustomValue.find_all_by_value(@billing)
    billings.each do |x|
    	@project_billing_ids << x.customized_id
    end if billings

    @projtype = params[:project_type]
    @project_type_ids = []
    projtypes = CustomValue.find_all_by_value(@projtype)
    projtypes.each do |x|
    	@project_type_ids << x.customized_id
    end if projtypes

    if @query == "user"
      @skill = CustomField.find_by_name("Skill or Role")
      if @skill
        @skill_values = [["All", "0"]]
	    	@skill.possible_values.each do |line|
	    		@skill_values << line
	    	end
	    end

	    @skill_selected = params[:skill]
      @skill_ids = []
      skill = CustomValue.find(:all, :conditions => ["value = ? and custom_field_id = ?", @skill_selected, @skill])
      skill.each do |x|
      	@skill_ids << x.customized_id
      end if skill

      @skill_ids = [0] if @skill_ids.empty? and @skill_selected != 0 and @skill_selected != nil
      available_user_conditions = []
      available_user_conditions << "\"users\".\"status\" = 1"
      available_user_conditions << eng_only
      available_user_conditions << ("id in (#{@skill_ids.join(',')})") if !@skill_ids.empty? and @skill_selected != "0" and @skill_selected != ""
      available_user_conditions << ( (params[:selectednames].blank?)? nil : "id not in (#{params[:selectednames].join(',')})")
      available_user_conditions = available_user_conditions.compact.join(" and ")
      @available_users = User.all(:select => user_select,
                                  :conditions => available_user_conditions,
                                  :order => user_order)
      
      selected_user_conditions = []
      selected_user_conditions << "\"users\".\"status\" = 1"
      selected_user_conditions << eng_only
      selected_user_conditions << ( (params[:selectednames].blank?)? "id is null" : "id in (#{params[:selectednames].join(',')})")
      selected_user_conditions = selected_user_conditions.compact.join(" and ")
      @selected_users = User.all(:select => user_select,
                                  :conditions => selected_user_conditions,
                                  :include => [:memberships],
                                  :order => user_order)
      @available_projects = Project.active.all(:select => project_select,
                                        :order => project_order )
      @selected_projects = []
    else


    	@project_billing_ids = [0] if @project_billing_ids.empty? and @billing != 0 and !@billing.nil?
    	@project_type_ids = [0] if @project_type_ids.empty? and @projtype != 0 and @projtype != nil
      available_project_conditions = []
      available_project_conditions << ( (@selected_acctype == 0)? nil : "\"projects\".\"acctg_type\" = #{params[:acctype]}")
      available_project_conditions << ( (params[:selectedprojects].blank?)? nil : "id not in (#{params[:selectedprojects].join(',')})")
			available_project_conditions << ("id in (#{@project_billing_ids.join(',')})") if !@project_billing_ids.empty? and @billing != "0" and !@billing.nil?
			available_project_conditions << ("id in (#{@project_type_ids.join(',')})") if !@project_type_ids.empty? and @projtype != "0" and @projtype != ""
      available_project_conditions = available_project_conditions.compact.join(" and ")
      #available_project_conditions = ( (params[:selectedprojects].blank?)? "" : "id not in (#{params[:selectedprojects].join(',')})")

      @available_projects = Project.active.all(:select => project_select,
                                        :conditions => available_project_conditions,
                                        :order => project_order)
      selected_project_conditions = ( (params[:selectedprojects].blank?)? "id is null" : "id in (#{params[:selectedprojects].join(',')})")
      @selected_projects = Project.active.all(:select => project_select,
                                       :conditions => selected_project_conditions,
                                       :order => project_order)
      selected_user_conditions = []
      selected_user_conditions << "\"users\".\"status\" = 1"
      selected_user_conditions << eng_only
      selected_user_conditions << ( (@selected_projects.size > 0)? "users.id in ( select m.user_id from members as m where m.project_id in( #{@selected_projects.collect(&:id).join(',')} ) )" : "id is null")
      selected_user_conditions = selected_user_conditions.compact.join(" and ")
      @selected_users = User.all( :select => user_select,
                                   :conditions => selected_user_conditions,
                                   :include => [:projects, {:memberships, :role }],
                                   :order => user_order)
                                   
      available_user_conditions = []
      available_user_conditions << "\"users\".\"status\" = 1"
      available_user_conditions << eng_only
      available_user_conditions << ((@selected_users.size > 0)? "id not in (#{@selected_users.collect(&:id).join(',')})" : nil )
      available_user_conditions = available_user_conditions.compact.join(" and ")
      @available_users = User.all(:select => user_select,
                                  :conditions => available_user_conditions,
                                  :order => user_order)
    end

    ####################SUMMARY COMPUTATION###################

    user_list = (@selected_users.size > 0)? "time_entries.user_id in (#{@selected_users.collect(&:id).join(',')}) and" : ""
    project_list = (@selected_projects.size > 0)? "time_entries.project_id in (#{@selected_projects.collect(&:id).join(',')}) and" : ""   
    bounded_time_entries_billable = TimeEntry.find(:all, 
                                :conditions => ["#{user_list} #{project_list} spent_on between ? and ? and issues.acctg_type = (select id from enumerations where name = 'Billable')",
                                @from, @to],
                                :include => [:project],
                                :joins => [:issue],
                                :order => "projects.name asc" )
    bounded_time_entries_billable.each{|v| v.billable = true }
    bounded_time_entries_non_billable = TimeEntry.find(:all, 
                                :conditions => ["#{user_list} #{project_list} spent_on between ? and ? and issues.acctg_type = (select id from enumerations where name = 'Non-billable')",
                                @from, @to],
                                :include => [:project],
                                :joins => [:issue],
                                :order => "projects.name asc" )
    bounded_time_entries_non_billable.each{|v| v.billable = false }
    time_entries = TimeEntry.find(:all, 
                                :conditions => ["#{user_list} spent_on between ? and ?", 
                                @from, @to] )                            
                               
    ######################################
    # th = total hours regardless of selected projects
    # tth = total hours on selected projects
    # tbh = total billable hours on selected projects
    # tnbh = total non-billable hours on selected projects
    ######################################
    @th = time_entries.collect(&:hours).compact.sum
    @tbh = bounded_time_entries_billable.collect(&:hours).compact.sum
    @tnbh = bounded_time_entries_non_billable.collect(&:hours).compact.sum
    @thos = (@tbh + @tnbh)
    @summary = []
    
    project_ids = @selected_projects.collect(&:id)
    @selected_users.each do |usr|
      if usr.class.to_s == "User"
        b = bounded_time_entries_billable.select{|v| v.user_id == usr.id }
        nb = bounded_time_entries_non_billable.select{|v| v.user_id == usr.id }
        x = Hash.new
        
        x[:location] = usr.location
        x[:name] = usr.name
        x[:skill] = usr.skill
        x[:entries] = b + nb
        x[:total_hours] = time_entries.select{|v| v.user_id == usr.id }.collect(&:hours).compact.sum
        x[:billable_hours] = b.collect(&:hours).compact.sum
        x[:non_billable_hours] = nb.collect(&:hours).compact.sum
        x[:forecasted_hours_on_selected] = usr.allocations((@from..@to), project_ids)
        x[:total_hours_on_selected] = x[:billable_hours] + x[:non_billable_hours]
        @summary.push(x)
      end
    end

    @summary = @summary.sort_by{|c| "#{c[:name]}" }
    
  end
end
