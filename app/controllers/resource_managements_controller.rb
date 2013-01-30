class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations
  menu_item :forecasts, :only => :forecasts
  menu_item :users, :only => :users
  menu_item :utilization, :only => :utilization

  helper :users, :custom_management, :custom_fields, :scrums, :resource_utilization, :resource_costs

  require 'json'

  before_filter :require_management
  before_filter :get_projects_members, :only => [:allocations]
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
    @skill_set = User::SKILLS  #.resource_skills.sort
    @categories = Project.project_categories.sort
  end

  def load_chart
    if params[:chart] == "forecast_billable"
      @users = User.engineers.find(:all, :order => "lastname ASC")
      @total_users = params[:total_users].to_i
      @selection = (params[:selection].blank? ? "last 6 months" : params[:selection])
      today = Date.today
      case @selection
        when "last month"
          @from, @to = (today - 1.month).beginning_of_month, (today - 1.month).end_of_month
        when "last 3 months"
          @from, @to = (today - 3.months).beginning_of_month, (today - 1.month).end_of_month
        when "last 6 months"
          @from, @to = (today - 6.months).beginning_of_month, (today - 1.month).end_of_month
        when "this year"
          @from, @to = today.beginning_of_year, (today + 3.month).end_of_month
        when "last year"
          @from, @to = (today - 1.year).beginning_of_year, (today - 1.year).end_of_year
      end
      key = @selection.downcase.gsub(' ', '_')
      data = (params['data'].blank? ? {} : params['data'].each {|k,v| params['data'][k] = JSON.parse(v)})
      refresh = (params['refresh'].blank? ? nil : key)
      handler = ForecastBillableJob.new(@from, @to, @selection, refresh, @users.collect {|u| u.id})
      @job = Delayed::Job.find(:first,
              :conditions => ["handler = ? AND run_at <> ?", "#{handler.to_yaml}", (Time.parse("12am") + 1.day)])
      enqueue_forecast_billable_job(handler, @job) if !File.exists?("#{RAILS_ROOT}/config/forecast_billable.json") || (!data.blank? && data[key].nil?) || refresh
    elsif params[:chart] == "resource_allocation"
      get_projects_members
      @categories = Project.project_categories.sort
    else
      get_projects_members
      @users = User.active.engineers
      @sel_skill = params[:skill_selection]
      @skill_set = ((@sel_skill.blank? or @sel_skill.eql?("All"))? User::SKILLS : [@sel_skill])
    end
    render :update do |page|
      page.replace_html "show_#{params[:chart]}".to_sym, :partial => "resource_managements/charts/#{params[:chart]}"
      page.show "zoom_#{params[:chart]}".to_sym
    end
  end

  def load_json
    @enqueued = params[:enqueued]
    @json = if File.exists?("#{RAILS_ROOT}/config/#{params['chart']}.json")
      File.read("#{RAILS_ROOT}/config/#{params['chart']}.json")
    else
      {}.to_json
    end
    render :json => JSON.parse(@json)
  end

  def allocations
    @categories = Project.project_categories
    if params[:sort] || params[:filters]
      render :update do |page|
        page.replace_html :mgt_allocations_table_container, :partial => "resource_managements/allocations/allocation_list"
      end
    end
  end

  def forecasts
    sort_init "lastname"
    sort_update %w(lastname location skill)
    
    conditions = forecast_conditions(params)
    get_forecast_list(sort_clause, conditions, params)

    render :template => 'resource_managements/forecasts.rhtml', :layout => !request.xhr?
  end

  def users
    sort_clear
    sort_init 'lastname', 'asc'
    sort_update 'login' => "#{User.table_name}.login",
                'firstname' => "#{User.table_name}.firstname",
                'lastname' => "#{User.table_name}.lastname",
                'is_engineering' => "#{User.table_name}.is_engineering",
                'hired_date' => "#{CustomValue.table_name}.value",
                'resignation_date' => "#{CustomValue.table_name}.value"

    if filters = params[:filters]
      @from, @to = get_date_range(params[:selection], params[:from], params[:to], params[:filters][:is_employed])
      # temporarily put in the controller
      c = User.generate_user_mgt_condition(filters)
      conditions = c.conditions
      conditions = (["custom_fields.name = E'Employment Start'"] + c.conditions).compact.join(' AND ') if params[:caption] == "Hired Date"
      conditions = (["custom_fields.name = E'Employment End'"] + c.conditions).compact.join(' AND ') if params[:caption] == "Resignation Date" && !filters[:is_employed].to_i.eql?(1)
      @location, @skill = filters[:location], filters[:skill_or_role]
      limit = per_page_option

      if filters[:is_employed] and !filters[:is_employed].blank? and filters[:is_employed].to_i.eql?(1)
        @users_count = User.find(:all, :include => [:custom_values => :custom_field], :conditions => conditions).reject {|v| to_date_safe(v.resignation_date) &&
                                                     to_date_safe(v.resignation_date) < @from.to_date || to_date_safe(v.hired_date) && to_date_safe(v.hired_date) > @to.to_date}.count
        @user_pages = Paginator.new self, @users_count, limit, params['page']
        @users = User.find(:all, :include => [:custom_values => :custom_field], :limit => limit, :offset => @user_pages.current.offset, :order => sort_clause,
                                                 :conditions => conditions).reject {|v| to_date_safe(v.resignation_date) && to_date_safe(v.resignation_date) < @from.to_date ||
                                                 to_date_safe(v.hired_date) && to_date_safe(v.hired_date) > @to.to_date}
      else
        @users_count = User.count(:all, :include => [:custom_values => :custom_field], :conditions => conditions)
        @user_pages = Paginator.new self, @users_count, limit, params['page']
        @users = User.find(:all, :include => [:custom_values => :custom_field], :limit => limit, :offset => @user_pages.current.offset, :order => sort_clause,
                                           :conditions => conditions)
      end
    end
    render :template => 'resource_managements/users.rhtml', :layout => !request.xhr?
  end

  def utilization
    sort_clear
    sort_init "lastname"
    sort_update %w(lastname)

    @selected_users = []
    utilization_filters(sort_clause)

    respond_to do |format|
      if params[:lazy_load].blank?
        format.html { render :layout => !request.xhr? }
      else
        format.js {render :layout => false}
      end
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
      if @user.employee_status == "Resigned" and @user.resignation_date.blank? || @user.resignation_date.to_date >= Date.today
        @user.errors.add_to_base "Please check employment end date."
        render :template => 'resource_managements/users/edit_user.rhtml', :layout => !request.xhr?
      else
        if @user.save
          if !@user.resignation_date.empty? && !@user.resignation_date.nil?
            if @user.resignation_date.to_date < Date.today
              employee_status_field_id = CustomField.find_by_name("Employee Status")
              @user.custom_values.find_by_custom_field_id(employee_status_field_id).update_attribute :value, "Resigned"
            end
          end
          Mailer.deliver_account_activated(@user) if was_activated
          flash[:notice] = l(:notice_successful_update)
          # Give a string to redirect_to otherwise it would use status param as the response code
          redirect_to(url_for(:action => 'users', :filters => params[:filters]))
        else
          render :template => 'resource_managements/users/edit_user.rhtml', :layout => !request.xhr?
        end
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

    conditions = forecast_conditions(params)
    get_forecast_list(clause, conditions, params)

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
    sort_clear
    sort_init 'users.lastname', 'asc'
    sort_update %w(projects.name enumerations.name users.lastname users.skill custom_values.value)
    user_conditions = []

    @projects = Project.development.find(:all, :include => [:accounting])
    project_ids = @projects.collect(&:id).join(',')
    unless params[:filters].blank?
      filters = params[:filters]
      @location, @role = filters[:location], filters[:skill_or_role]
      user_conditions << "users.location = '#{@location}'" unless filters[:location].blank?
      user_conditions << "users.skill = '#{@role}'" unless filters[:skill_or_role].blank?
      project_ids = filters[:projects].join(',') if filters[:projects]
    end
    @members = Member.find(:all, :include => [:user, {:project, [:custom_values => :custom_field]}, {:project, :accounting}],
                           :conditions => (["members.proj_team = true AND members.project_id IN (#{project_ids}) AND custom_fields.name = E'Category'"] + user_conditions).compact.join(' AND '),
                           :order => sort_clause).select {|m| !m.user.is_resigned}
  end

  def get_forecast_list(order, query, filters)
    limit = per_page_option
    dev_projects = Project.development.find(:all, :include => [:accounting])
    acctg = params[:acctg].to_s.blank? ? "Billable" : params[:acctg]
    if acctg.eql?('Both')
      @projects = dev_projects.collect {|p| p.id if (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable'))}.compact.uniq
    else
      @projects = dev_projects.collect {|p| p.id if (p.accounting_type.eql?(acctg))}.compact.uniq
    end

    if @projects.empty?
      @resources = []
    else
      if filters[:is_employed] and !filters[:is_employed].blank? and filters[:is_employed].to_i.eql?(1)
        @available_resources = User.find(:all, :conditions => query, :order => order, :include => [:projects, :members]).reject {|v| to_date_safe(v.resignation_date) && to_date_safe(v.resignation_date) < @from.to_date ||
                                                         to_date_safe(v.hired_date) && to_date_safe(v.hired_date) > @to.to_date}
        query << " and projects.id IN (#{@projects.join(', ')})"
        @resources_no_limit = User.find(:all, :conditions => query, :order => order, :include => [:projects, :members]).reject {|v| to_date_safe(v.resignation_date) && to_date_safe(v.resignation_date) < @from.to_date ||
                                                         to_date_safe(v.hired_date) && to_date_safe(v.hired_date) > @to.to_date}
        @resource_count = @resources_no_limit.count
        @resource_pages = Paginator.new self, @resource_count, limit, params['page']
        offset = @resource_pages.current.offset
        @resources = []
        (offset ... (offset + limit)).each do |i|
          break if @resources_no_limit[i].nil?
          @resources << @resources_no_limit[i]
          end


      else
        @available_resources = User.find(:all, :conditions => query, :order => order, :include => [:projects, :members])
        query << " and projects.id IN (#{@projects.join(', ')})"
        @resources_no_limit = User.find(:all, :conditions => query, :order => order, :include => [:projects, :members])
        @resource_count = @resources_no_limit.count
        @resource_pages = Paginator.new self, @resource_count, limit, params['page']
        offset = @resource_pages.current.offset
        @resources = []
        (offset ... (offset + limit)).each do |i|
          break if @resources_no_limit[i].nil?
          @resources << @resources_no_limit[i]
          end
      end
    end
    @skill_set = User::SKILLS
  end

  def delay_job
    @from, @to = get_date_range(params[:selection], params[:from], params[:to], params[:is_employed])

    acctg = params[:acctg].to_s.blank? ? "Billable" : params[:acctg]
    resources_no_limit = @resources_no_limit.collect {|r| r.id }
    handler = ForecastJob.new(@from, @to, acctg, resources_no_limit, @skill_set, @projects, params[:total_res_available])
    job = Delayed::Job.find_by_handler(handler.to_yaml)
    job = nil if job and job.run_at.eql?(Time.parse("12am") + 1.day)
    Delayed::Job.enqueue handler if job.blank?
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

  def utilization_filters(usr_order)
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
    @columns = (params[:columns] && %w(year month week day).include?(params[:columns])) ? params[:columns] : 'week'
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
    user_select = "id, firstname, lastname, status, location, skill"
    user_order = usr_order
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
#      @skill = CustomField.find_by_name("Skill or Role")
#      if @skill
#        @skill_values = [["All", "0"]]
#       @skill.possible_values.each do |line|
#         @skill_values << line
#       end
#     end

#     @location = CustomField.find_by_name("Location")
#      if @location
#        @location_values = [["All", "0"]]
#       @location.possible_values.each do |line|
#         @location_values << line
#       end
#     end

      @skill_selected = params[:skill]
      @location_selected = params[:location]
      available_user_conditions = []
      available_user_conditions << "\"users\".\"status\" = 1"
      available_user_conditions << eng_only
      available_user_conditions << "skill = '#{@skill_selected}'" if !@skill_selected.blank? and !@skill_selected.eql?("All")
      available_user_conditions << "location = '#{@location_selected}'" if !@location_selected.blank? and !@location_selected.eql?("All")
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
      user_default_query = ((params[:columns].blank?)? available_user_conditions : selected_user_conditions)

      @selected_users = User.all(:select => user_select,
                                  :conditions => user_default_query,
                                  :include => [:memberships],
                                  :order => user_order,
                                  :limit => 10,
                                  :offset => params[:offset].to_i)
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
                                   :order => user_order,
                                   :limit => 10,
                                   :offset => params[:offset].to_i)

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

    from, to = ((params[:from] && params[:to])? [@from, @to] : [(Date.today - 4.weeks), Date.today])
    project_ids = (@selected_projects.any? ? @selected_projects.collect(&:id) : @available_projects.collect(&:id))
    @selected_users.each do |usr|
      if usr.class.to_s == "User"
        b = bounded_time_entries_billable.select{|v| v.user_id == usr.id }
        nb = bounded_time_entries_non_billable.select{|v| v.user_id == usr.id }
        x = Hash.new

        x[:id] = usr.id
        x[:location] = usr.location
        x[:name] = usr.display_name
        x[:skill] = usr.skill
        x[:entries] = b + nb
        x[:total_hours] = time_entries.select{|v| v.user_id == usr.id }.collect(&:hours).compact.sum
        x[:billable_hours] = b.collect(&:hours).compact.sum
        x[:non_billable_hours] = nb.collect(&:hours).compact.sum
        x[:forecasted_hours_on_selected] = usr.total_expected(from, to, project_ids)
        x[:total_hours_on_selected] = x[:billable_hours] + x[:non_billable_hours]
        @summary.push(x)
      end
    end

  end

  def forecast_conditions(params)
    location = skill = lastname = nil
    location = ((params[:location].eql?('N/A') or params[:location].blank?)? nil : params[:location])
    skill = ((params[:skill].eql?('N/A') or params[:skill].blank?)? nil : params[:skill])
    lastname = (params[:lastname].blank? ? nil : params[:lastname].capitalize)

    @from, @to = get_date_range(params[:selection], params[:from], params[:to], params[:is_employed])

    custom_filters = Hash.new
    # in resource cost forecast summary, resources must be 'active.engineers'
    custom_filters[:is_engineering] = '1'
    custom_filters[:is_employed] = params[:is_employed] unless params[:is_employed].blank?

    conditions = Array.new
    conditions << User.generate_user_mgt_condition(custom_filters).conditions
    conditions << "location = '#{location}'" if location
    conditions << "skill = '#{skill}'" if skill
    conditions << "lastname = '#{lastname}'" if lastname
    conditions = conditions.compact.join(' and ')
  end

  def enqueue_forecast_billable_job(handler, job)
    unless job
      puts "enqueuing forecast vs billable job..."
      @job = Delayed::Job.enqueue handler
    else
      @job = nil
    end
  end

end
