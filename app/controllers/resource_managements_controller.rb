class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations
  menu_item :forecasts, :only => :forecasts
  menu_item :users, :only => :users
  menu_item :utilization, :only => :utilization

  include FaceboxRender
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
    @skill_set = User::SKILLS #.resource_skills.sort
    @categories = Project.project_categories.sort
  end

  def load_chart
    if params[:chart] == "forecast_billable"
      @users = User.engineers.find(:all, :order => "lastname ASC")
      @total_users = params[:total_users].to_i
      @selection = (params[:selection].blank? ? "current" : params[:selection])
      today = Date.today
      case @selection
        when "current"
          @from, @to = (today - 2.month).beginning_of_month, (today + 3.month).end_of_month
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
      data = (params['data'].blank? ? {} : params['data'].each { |k, v| params['data'][k] = JSON.parse(v) })
      refresh = (params['refresh'].blank? ? nil : key)
      handler = ForecastBillableJob.new(@from, @to, @selection, refresh, @users.collect { |u| u.id })
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
      @skill_set = ((@sel_skill.blank? or @sel_skill.eql?("All")) ? User::SKILLS : [@sel_skill])
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
    @engineers = User.engineers
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
        @users_count = User.find(:all, :include => [:custom_values => :custom_field], :conditions => conditions).reject { |v| to_date_safe(v.resignation_date) &&
            to_date_safe(v.resignation_date) < @from.to_date || to_date_safe(v.hired_date) && to_date_safe(v.hired_date) > @to.to_date }.count
        @user_pages = Paginator.new self, @users_count, limit, params['page']
        @users = User.find(:all, :include => [:custom_values => :custom_field], :limit => limit, :offset => @user_pages.current.offset, :order => sort_clause,
                           :conditions => conditions).reject { |v| to_date_safe(v.resignation_date) && to_date_safe(v.resignation_date) < @from.to_date ||
            to_date_safe(v.hired_date) && to_date_safe(v.hired_date) > @to.to_date }
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
        format.js { render :layout => false }
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
        new_projects = params[:projects].collect { |p| Member.new(:project_id => p.to_i, :role_id => params[:membership][:role_id].to_i) }
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

    from, to = get_date_range(params[:selection], params[:from], params[:to], params[:is_employed])

    accounting = params[:acctg].to_s.blank? ? "Billable" : params[:acctg]
    resources_no_limit = @resources_no_limit.collect { |r| r.id }
    skill_set = @skill_set
    projects = @projects
    total_available_resources = params[:total_res_available]

    mgt = {}

    @resources_no_limit = User.find(:all, :conditions => ["id IN (#{resources_no_limit.join(',')})"])
    @projects = projects

    forecasts, summary = {}, {}
    updated_at = Time.now

    resource_count = {}
    skill_allocations = {}

    weeks = get_weeks_range(from.to_date, to.to_date)
    weeks.each do |week|
      weekly_resources_count = 0
      forecasts_this_week = forecasts[week.last] || {}
      summary_this_week = summary[week.last] || {}
      summary_this_week["resource_count"] = {}
      summary_this_week["resource_count_per_day"] = {}

      @resources_no_limit.each do |resource|
        resignation_date = to_date_safe(resource.resignation_date)
        hired_date = to_date_safe(resource.hired_date)
        start_date = hired_date && hired_date > week.first && hired_date < week.last ? hired_date : week.first
        end_date = resignation_date && resignation_date > week.first && resignation_date < week.last ? resignation_date : week.last
        total_working_days = (start_date..end_date).count
        working_days = 0
        alloc = resource.allocations(week, @projects)

        project_allocations = resource.members.collect(&:resource_allocations).flatten.select do |v|
          @projects.include? v.member.project_id
        end
        if allocations = project_allocations.select { |a| a.start_date <= week.last && a.end_date >= week.first }.uniq
          allocations.each do |allocation|
            working_days = total_working_days - detect_holidays_in_week(allocation.location, week)
          end
        end
        skill = resource.skill
        skill_allocations[skill] ||= 0
        skill_allocations[skill] += alloc unless resource.is_resigned
        resource_count[skill] ||= 0
        resource_count[skill] += 1 if alloc.zero? && !resource.is_resigned || alloc < working_days && !resource.is_resigned

        if resignation_date && resignation_date > week.first && hired_date && hired_date < week.last
          weekly_resources_count += 1
        elsif !resignation_date && hired_date && hired_date < week.last
          weekly_resources_count += 1
        end

        forecasts_this_week[resource.id] = working_days.eql?(0) ? 0 : alloc/working_days
      end

      current_total_available_resources = 0
      current_total_allocated_resources = 0

      skill_set.each do |skill|
        current_total_available_resources += resource_count[skill].to_i
        resource_count_per_day = skill_allocations[skill].to_f/week.count.to_f
        current_total_allocated_resources += resource_count_per_day

        summary_this_week["resource_count"][skill] = resource_count[skill].to_i
        summary_this_week["resource_count_per_day"][skill] = resource_count_per_day
        resource_count[skill] = 0
        skill_allocations[skill] = 0.0
      end

      percent_unallocated = (current_total_available_resources.to_f / weekly_resources_count.to_f) * 100
      percent_allocated = 100 - percent_unallocated
      total_allocated_percent = (current_total_allocated_resources / weekly_resources_count.to_f) * 100

      # TODO: apply holidays
      summary_this_week["total_days"] = week.count
      summary_this_week["percent_allocated"] = percent_allocated
      summary_this_week["percent_unallocated"] = percent_unallocated
      summary_this_week["total_allocated_percent"] = total_allocated_percent
      summary_this_week["weekly_resources_count"] = weekly_resources_count
      summary_this_week["current_total_available_resources"] = current_total_available_resources
      summary_this_week["current_total_allocated_resources"] = current_total_allocated_resources

      forecasts[week.last] = forecasts_this_week
      summary[week.last] = summary_this_week
    end

    mgt = {"forecasts" => forecasts, "updated_at" => updated_at, "summary" => summary}

    @forecasts = {}
    @summary = {}


    @forecasts = mgt["forecasts"]
    @summary = mgt["summary"]
    render :update do |page|
      page.replace_html :weekly_forecasts_panel, :partial => 'resource_managements/forecasts/weeks',
                        :locals => {:total_res_available => params[:total_res_available].to_i}
    end

  end

  def resource_billing_detail
    month = params[:month] && !params[:month].empty? ? Date::ABBR_MONTHNAMES.index(params[:month]) : Date.today.month
    tick_month = params[:month] && !params[:month].empty? ? params[:month] : Date::ABBR_MONTHNAMES[Date.today.month]
    year = params[:date][:year]
    @tick = "#{tick_month} #{year}"
    @rb = Hash.new
    @per_user = Hash.new
    @overall_forcasted_hours = 0.0
    @overall_actual_hours = 0.0
    @beginning_of_month = Date.new(year.to_i, month, 1)
    @end_of_month = @beginning_of_month.end_of_month
    @users = User.engineers.find(:all, :order => "lastname ASC, firstname ASC")

    @users.each do |user|
      get_resource_billing_detail(user, @beginning_of_month, @end_of_month)
    end
  end

  def project_billing_detail
    month = params[:month] && !params[:month].empty? ? Date::ABBR_MONTHNAMES.index(params[:month]) : Date.today.month
    tick_month = params[:month] && !params[:month].empty? ? params[:month] : Date::ABBR_MONTHNAMES[Date.today.month]
    year = params[:date][:year]
    @tick = "#{tick_month} #{year}"
    @pb = Hash.new
    @per_project = Hash.new
    @overall_forcasted_hours = 0.0
    @overall_actual_hours = 0.0
    @beginning_of_month = Date.new(year.to_i, month, 1)
    @end_of_month = @beginning_of_month.end_of_month
    @projects = Project.development.select { |v| v.planned_start_date && v.planned_start_date <= @end_of_month &&
        v.planned_end_date && v.planned_end_date >= @beginning_of_month && v.accounting_type == 'Billable' }
    @projects.each do |proj|
      get_project_billing_details(proj, @beginning_of_month, @end_of_month)
    end
  end

  def export_resource_billing_detail
    month = params[:month] && !params[:month].empty? ? Date::ABBR_MONTHNAMES.index(params[:month]) : Date.today.month
    tick_month = params[:month] && !params[:month].empty? ? params[:month] : Date::ABBR_MONTHNAMES[Date.today.month]
    year = params[:year]
    @rb = Hash.new
    @per_user = Hash.new
    @overall_forcasted_hours = 0.0
    @overall_actual_hours = 0.0
    beginning_of_month = Date.new(year.to_i, month, 1)
    end_of_month = beginning_of_month.end_of_month
    users = User.engineers.find(:all, :order => "lastname ASC, firstname ASC")

    resource_csv = FasterCSV.generate do |csv|
      # header row
      csv << ["Project Billing Report for #{tick_month} #{year}"]
      csv << ['']
      csv << ['Name', "Project", "SOW Rate", "Allocated Hours", "Allocated Cost", "Actual Hours", "Billable Amount", "Billable Hours", "Actual Billable"]

      users.each do |user|
        get_resource_billing_detail(user, beginning_of_month, end_of_month)
        h_date, r_date = to_date_safe(user.hired_date), to_date_safe(user.resignation_date)
        unless (h_date && h_date > end_of_month) || (r_date && r_date < beginning_of_month)
          members = user.members

          csv << ["#{user.lastname}, #{user.firstname}"]

          members.each do |member|
            res_alloc = member.resource_allocations.select { |alloc| alloc.start_date <= end_of_month && alloc.end_date >= beginning_of_month }
            if res_alloc && !res_alloc.empty? && @rb["#{member.id}"]

              csv << ['', @rb["#{member.id}"][:project], @rb["#{member.id}"][:sow_rate],
                      "%.2f" % @rb["#{member.id}"][:allocated_hours], "%.2f" % @rb["#{member.id}"][:allocated_cost],
                      "%.2f" % @rb["#{member.id}"][:actual_hours], "%.2f" % @rb["#{member.id}"][:billable_amount],
                      "%.2f" % @rb["#{member.id}"][:billable_hours], "%.2f" % @rb["#{member.id}"][:actual_billable]]
            end
          end
        end
        if @per_user["#{user.id}"]
          csv << ['', '', '', "%.2f" % @per_user["#{user.id}"][:total_allocated_hours],
                  "%.2f" % @per_user["#{user.id}"][:total_allocated_cost],
                  "%.2f" % @per_user["#{user.id}"][:total_actual_hours],
                  "%.2f" % @per_user["#{user.id}"][:total_billable_amount],
                  "%.2f" % @per_user["#{user.id}"][:total_billable_hours],
                  "%.2f" % @per_user["#{user.id}"][:total_actual_billable]]
        end
      end
    end
    send_data(resource_csv, :type => 'text/csv', :filename => "#{params[:month]}_#{params[:year]}_resource_billing_details.csv")
  end

  def export_project_billing_detail
    month = params[:month] && !params[:month].empty? ? Date::ABBR_MONTHNAMES.index(params[:month]) : Date.today.month
    tick_month = params[:month] && !params[:month].empty? ? params[:month] : Date::ABBR_MONTHNAMES[Date.today.month]
    year = params[:year]
    @tick = "#{tick_month} #{year}"
    @pb = Hash.new
    @per_project = Hash.new
    @overall_forcasted_hours = 0.0
    @overall_actual_hours = 0.0
    @beginning_of_month = Date.new(year.to_i, month, 1)
    @end_of_month = @beginning_of_month.end_of_month
    @projects = Project.development.select { |v| v.planned_start_date && v.planned_start_date <= @end_of_month &&
        v.planned_end_date && v.planned_end_date >= @beginning_of_month && v.accounting_type == 'Billable' }

    project_csv = FasterCSV.generate do |csv|
      # header row
      csv << ["Project Billing Report for #{tick_month} #{year}"]
      csv << ['']
      csv << ['Project', "Name", "Default Rate", "SOW Rate", "Allocated Hours", "Allocated Cost", "Actual Hours", "Billable Amount", "Billable Hours", "Actual Billable"]


      @projects.each do |proj|
        get_project_billing_details(proj, @beginning_of_month, @end_of_month)
        bm = Project.find_by_id(proj.id).billing_model
        csv << ["#{proj.name}: #{bm}"]

        members = proj.members.sort_by { |x| [x.user.lastname, x.user.firstname] }

        members.each do |member|
          if @pb["#{member.id}"]
            csv << ['', @pb["#{member.id}"][:name], @pb["#{member.id}"][:default_rate], @pb["#{member.id}"][:sow_rate],
                    "%.2f" % @pb["#{member.id}"][:allocated_hours], "%.2f" % @pb["#{member.id}"][:allocated_cost],
                    "%.2f" % @pb["#{member.id}"][:actual_hours], "%.2f" % @pb["#{member.id}"][:billable_amount],
                    "%.2f" % @pb["#{member.id}"][:billable_hours], "%.2f" % @pb["#{member.id}"][:actual_billable]]
          end
        end
        csv << ['', '', '', '', "%.2f" % @per_project["#{proj.id}"][:total_allocated_hours],
                "%.2f" % @per_project["#{proj.id}"][:total_allocated_cost],
                "%.2f" % @per_project["#{proj.id}"][:total_actual_hours],
                "%.2f" % @per_project["#{proj.id}"][:total_billable_amount],
                "%.2f" % @per_project["#{proj.id}"][:total_billable_hours],
                "%.2f" % @per_project["#{proj.id}"][:total_actual_billable]]
      end
    end
    send_data(project_csv, :type => 'text/csv', :filename => "#{params[:month]}_#{params[:year]}_project_billing_details.csv")
  end

  def forecasts_billable_detail
    sort_clear
    sort_init "lastname"
    sort_update %w(lastname skill location)

    @a = Hash.new
    @total_billable_hours, @total_forecasted_hours, @billable_resources_count = 0, 0, 0
    @total_available_hours, @total_available_hours_with_holidays, @total_billable_revenue = 0, 0, 0

    @tick = "#{params[:tick]}".split(/ /)
    month = Date::ABBR_MONTHNAMES.index(@tick[0])
    from = Date.new(@tick[1].to_i, month, 1)
    to = from.end_of_month

    @users = User.engineers.find(:all, :order => sort_clause)
    @users.each do |u|
      h_date, r_date = to_date_safe(u.hired_date), to_date_safe(u.resignation_date)
      unless (h_date && h_date >= to) || (r_date && r_date <= from)
        compute_details((from..to), u, u.members.all, "billable")
      end
    end
    render :template => 'resource_managements/forecasts_billable_detail.rhtml', :layout => !request.xhr?
  end

  def export_weekly_actual_hours
    month = params[:month] && !params[:month].empty? ? Date::ABBR_MONTHNAMES.index(params[:month]) : Date.today.month
    tick_month = params[:month] && !params[:month].empty? ? params[:month] : Date::ABBR_MONTHNAMES[Date.today.month]
    year = params[:year]
    @tick = "#{tick_month} #{year}"
    @pb = Hash.new
    @per_project = Hash.new
    @overall_forcasted_hours = 0.0
    @overall_actual_hours = 0.0
    @beginning_of_month = Date.new(year.to_i, month, 1)
    @end_of_month = @beginning_of_month.end_of_month
    @projects = Project.development.select { |v| v.planned_start_date && v.planned_start_date <= @end_of_month &&
        v.planned_end_date && v.planned_end_date >= @beginning_of_month }
    weeks = get_weeks_range(@beginning_of_month, @end_of_month)
    week_array = []
    week_array2 = []
    weeks.each do |week|
      week_array << "#{week.first} - #{week.last}"
      week_array2 << week.last
    end
    project_csv = FasterCSV.generate do |csv|
      # header row
      csv << ["Weekly Project Billing Report for #{tick_month} #{year}"]
      csv << ['']
      csv << ['', '', '', '', "#{week_array[0]}", '',"#{week_array[1]}", '', "#{week_array[2]}", '', "#{week_array[3]}"]
      csv << ['Project', "Name", "Role","Allocated Hours", "Actual Hours","Allocated Hours", "Actual Hours","Allocated Hours", "Actual Hours","Allocated Hours", "Actual Hours"]


      @projects.each do |proj|
        get_project_billing_details_weekly(proj, @beginning_of_month, @end_of_month)

        members = proj.members.sort_by { |x| [x.user.lastname, x.user.firstname] }

        members.each do |member|
          res_alloc = member.resource_allocations.select { |alloc| alloc.start_date <= @end_of_month && alloc.end_date >= @beginning_of_month }
          if @pb && member && proj && res_alloc && !res_alloc.empty?
            csv << ["#{proj.name}", @pb["#{member.id}"][:name], "#{member.user.skill}",
                    @pb["#{member.id}"]["allocated_hours_#{week_array2[0]}"] ? @pb["#{member.id}"]["allocated_hours_#{week_array2[0]}"] : 0.0,
                    @pb["#{member.id}"]["actual_hours_#{week_array2[0]}"] ? @pb["#{member.id}"]["actual_hours_#{week_array2[0]}"] : 0.0,
                    @pb["#{member.id}"]["allocated_hours_#{week_array2[1]}"] ? @pb["#{member.id}"]["allocated_hours_#{week_array2[1]}"] : 0.0,
                    @pb["#{member.id}"]["actual_hours_#{week_array2[1]}"] ? @pb["#{member.id}"]["actual_hours_#{week_array2[1]}"] : 0.0,
                    @pb["#{member.id}"]["allocated_hours_#{week_array2[2]}"] ? @pb["#{member.id}"]["allocated_hours_#{week_array2[2]}"] : 0.0,
                    @pb["#{member.id}"]["actual_hours_#{week_array2[2]}"] ? @pb["#{member.id}"]["actual_hours_#{week_array2[2]}"] : 0.0,
                    @pb["#{member.id}"]["allocated_hours_#{week_array2[3]}"] ? @pb["#{member.id}"]["allocated_hours_#{week_array2[3]}"] : 0.0,
                    @pb["#{member.id}"]["actual_hours_#{week_array2[3]}"] ? @pb["#{member.id}"]["actual_hours_#{week_array2[3]}"] : 0.0]
          end
        end
      end
    end
    send_data(project_csv, :type => 'text/csv', :filename => "#{params[:month]}_#{params[:year]}_weekly_logged_details.csv")

  end

  def export
    sort_clause = params[:order]
    @a = Hash.new
    @total_billable_hours, @total_forecasted_hours, @billable_resources_count = 0, 0, 0
    @total_available_hours, @total_available_hours_with_holidays, @total_billable_revenue = 0, 0, 0

    @tick = "#{params[:tick]}".split(/ /)
    month = Date::ABBR_MONTHNAMES.index(@tick[0])
    from = Date.new(@tick[1].to_i, month, 1)
    to = from.end_of_month

    @users = User.engineers.find(:all, :order => sort_clause)
    @users.each do |u|
      h_date, r_date = to_date_safe(u.hired_date), to_date_safe(u.resignation_date)
      unless (h_date && h_date >= to) || (r_date && r_date <= from)
        compute_details((from..to), u, u.members.all, "billable")
      end
    end

    users_csv = FasterCSV.generate do |csv|
      # header row
      csv << ['', '', '', '', '', '', '', '', '', '', '', '', "Total Billable Hours", @total_available_hours]
      csv << ['', '', '', '', '', '', '', '', '', '', '', '', "Billable Resources", @billable_resources_count]
      csv << ['', '', '', '', '', '', '', '', '', '', '', '', "Expected Billable Hours", @total_available_hours_with_holidays, '', "Total Forecasted Hours",
              @total_forecasted_hours, '', "Actual Hours", @total_billable_hours]
      csv << ['', '', '', '', '', '', '', '', '', '', '', '', "Expected Billable Revenue", @total_billable_revenue]
      csv << ['', '', '', '', '', '', '', '', '', '', '', '', "85% Billability", "%.2f" % (@total_available_hours * 0.85), '', "% Forecast Allocation",
              "%.2f" % (@total_forecasted_hours/@total_available_hours * 100), '',
              "% Actual Billable", "%.2f" % (@total_billable_hours/@total_available_hours * 100)]
      csv << []
      csv << ["Firstname", "Lastname", "Role", "Location", "Hired Date", "End Date", "Status", "Allocation", "Days",
              "Avail Hrs", "Days (Excl Hol)", "Available hours (Excl Hol)", "Rate", "Billable Revenue", "Project Allocation",
              "Allocation Cost", "SOW Rate", "Variance", "Billed Hours", "Billed Amount", "SOW Rate", "Variance"]

      # data rows
      @users.each do |user|
        if @a["#{user.login}"]
          csv << [@a["#{user.login}"][:firstname], @a["#{user.login}"][:lastname], @a["#{user.login}"][:skill],
                  @a["#{user.login}"][:location], @a["#{user.login}"][:hired_date],
                  @a["#{user.login}"][:end_date] ? @a["#{user.login}"][:end_date] : "",
                  @a["#{user.login}"][:status], "100%", @a["#{user.login}"][:available_with_holidays],
                  @a["#{user.login}"][:available_hours_with_holidays], @a["#{user.login}"][:available_days],
                  @a["#{user.login}"][:available_hours], @a["#{user.login}"][:default_rate], @a["#{user.login}"][:revenue],
                  @a["#{user.login}"][:project_allocation], @a["#{user.login}"][:allocation_cost],
                  @a["#{user.login}"][:project_allocation] > 0 ? "#{"%.2f" % (@a["#{user.login}"][:allocation_cost]/@a["#{user.login}"][:project_allocation])}" : 0,
                  @a["#{user.login}"][:project_allocation] - @a["#{user.login}"][:available_hours],
                  @a["#{user.login}"][:billable_hours], @a["#{user.login}"][:billed_amount],
                  @a["#{user.login}"][:billable_hours] > 0 ? "#{"%.2f" % (@a["#{user.login}"][:billed_amount]/@a["#{user.login}"][:billable_hours])}" : 0,
                  @a["#{user.login}"][:billable_hours] - @a["#{user.login}"][:project_allocation]]
        end
      end
    end

    send_data(users_csv, :type => 'text/csv', :filename => "#{params[:tick].gsub(' ', '_')}details.csv")
  end

  def default_rate
    sort_clear
    sort_init "lastname"
    sort_update %w(lastname skill default_rate effective_date)

    available_user_conditions = []
    @skill_selected = params[:filter_by] ? params[:filter_by] : params[:skill] || "N/A"
    available_user_conditions << "skill = '#{@skill_selected}'" if !@skill_selected.blank? and !@skill_selected.eql?("N/A")

    @resources = User.active.engineers.find(:all, :conditions => available_user_conditions, :order => sort_clause)
    render :template => 'resource_managements/default_rate.rhtml', :layout => !request.xhr?
  end


  def set_rate
    if params[:cancel]
      render_updates(true)
    else
      @resource = User.find(:all, :conditions => ["id = ?", params[:user_id]])
      respond_to do |format|
        format.html
        format.js { render_to_facebox :partial => "resource_managements/default_rate/set_rate" }
      end
    end
  end

  def multiple_set_rate
    if params[:cancel]
      render_updates(true)
    else
      resources = params[:resource_ids] ? (params[:resource_ids]).reject { |l| l =~ /[on]/ } : []
      resources << params[:user_id] if params[:user_id]
      @resources = User.find(:all, :conditions => ["id in (?)", resources])
      @resource_list = @resources.map(&:name)
      respond_to do |format|
        format.html
        format.js { render_to_facebox :partial => "resource_managements/default_rate/multiple_set_rate" }
      end
    end
  end

  def save_default_rate
    users = params[:res_ids].split(',').map(&:to_i)
    default_rate = params[:user][:default_rate]
    effective_date = params[:user][:effective_date]
    users.each do |user|
      u = User.find(user)
      if u.default_rate && u.effective_date && default_rate && u.default_rate != default_rate.to_f && !effective_date.blank? && u.effective_date < to_date_safe(effective_date)
        history = RateHistory.new
        history.default_rate = u.default_rate
        history.user_id = u.id
        history.effective_date = u.effective_date
        history.end_date = effective_date
        history.save
      end
      u.update_attributes :default_rate => default_rate, :effective_date => effective_date
    end
    redirect_to :action => "default_rate", :controller => "resource_managements", :filter_by => params[:filter_by]
  end

  def show_rate_history
    if params[:cancel]
      render_updates(true)
    else
      @resource = User.find_by_id(params[:user_id])
      @rate_history = @resource.rate_histories
      respond_to do |format|
        format.html
        format.js { render_to_facebox :partial => "resource_managements/default_rate/show_rate_history" }
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
                           :order => sort_clause).select { |m| !m.user.is_resigned }
  end

  def get_forecast_list(order, query, filters)
    limit = per_page_option
    dev_projects = Project.development.find(:all, :include => [:accounting])
    acctg = params[:acctg].to_s.blank? ? "Billable" : params[:acctg]
    if acctg.eql?('Both')
      @projects = dev_projects.collect { |p| p.id if (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable')) }.compact.uniq
    else
      @projects = dev_projects.collect { |p| p.id if (p.accounting_type.eql?(acctg)) }.compact.uniq
    end

    if @projects.empty?
      @resources = []
    else
      if filters[:is_employed] and !filters[:is_employed].blank? and filters[:is_employed].to_i.eql?(1)
        @available_resources = User.find(:all, :conditions => query, :order => order, :include => [:projects, :members]).reject { |v| to_date_safe(v.resignation_date) && to_date_safe(v.resignation_date) < @from.to_date ||
            to_date_safe(v.hired_date) && to_date_safe(v.hired_date) > @to.to_date }
        #query << " and projects.id IN (#{@projects.join(', ')})"
        @resources_no_limit = User.find(:all, :conditions => query, :order => order, :include => [:projects, :members]).reject { |v| to_date_safe(v.resignation_date) && to_date_safe(v.resignation_date) < @from.to_date ||
            to_date_safe(v.hired_date) && to_date_safe(v.hired_date) > @to.to_date }
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
        #query << " and projects.id IN (#{@projects.join(', ')})"
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

  def render_empty_weeks
    render :update do |page|
      page.replace_html :weekly_forecasts_panel, :partial => 'resource_managements/forecasts/empty_weeks',
                        :locals => {:total_res_available => params[:total_res_available].to_i}
      page.hide :icon_reload_forecasts
      page.hide :updated_at_text
    end
  end

# Retrieves the date range based on predefined ranges or specific from/to param dates
  def retrieve_date_range(period_type, period)
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
      begin
        ; @from = params[:from].to_s.to_date unless params[:from].blank?;
      rescue;
      end
      begin
        ; @to = params[:to].to_s.to_date unless params[:to].blank?;
      rescue;
      end
      begin
        ; @from = params[:leaves_from].to_s.to_date unless params[:leaves_from].blank?;
      rescue;
      end
      begin
        ; @to = params[:leaves_to].to_s.to_date unless params[:leaves_to].blank?;
      rescue;
      end
      @free_period = true
    else
      # default
      current_month
    end

    @from, @to = @to, @from if @from && @to && @from > @to
    @from ||= (TimeEntry.minimum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_time_entries)) || Date.today) - 1
    @to ||= (TimeEntry.maximum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_time_entries)) || Date.today)
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
    @query = (params[:query].blank?) ? "user" : params[:query]
    @disable_acctype_options = (@query == "user") ? true : false
    @eng_only, eng_only = (params[:eng_only] == "1" || params[:right].blank?) ? [true, "is_engineering = true"] : [false, nil]
    @for_acctg = (params[:for_acctg] == "1") ? true : false
    @show_only = (params[:show_only].blank?) ? "both" : params[:show_only]
    @tall ||= []

    @selected_acctype = ((params[:acctype].blank?) ? "" : params[:acctype]).to_i
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

      @skill_selected = params[:skill]
      @location_selected = params[:location]
      available_user_conditions = []
      available_user_conditions << "\"users\".\"status\" = 1"
      available_user_conditions << eng_only
      available_user_conditions << "skill = '#{@skill_selected}'" if !@skill_selected.blank? and !@skill_selected.eql?("All")
      available_user_conditions << "location = '#{@location_selected}'" if !@location_selected.blank? and !@location_selected.eql?("All")
      available_user_conditions << ((params[:selectednames].blank?) ? nil : "id not in (#{params[:selectednames].join(',')})")
      available_user_conditions = available_user_conditions.compact.join(" and ")
      @available_users = User.all(:select => user_select,
                                  :conditions => available_user_conditions,
                                  :order => user_order)

      selected_user_conditions = []
      selected_user_conditions << "\"users\".\"status\" = 1"
      selected_user_conditions << eng_only
      selected_user_conditions << ((params[:selectednames].blank?) ? "id is null" : "id in (#{params[:selectednames].join(',')})")
      selected_user_conditions = selected_user_conditions.compact.join(" and ")
      user_default_query = ((params[:columns].blank?) ? available_user_conditions : selected_user_conditions)

      @selected_users = User.all(:select => user_select,
                                 :conditions => user_default_query,
                                 :include => [:memberships],
                                 :order => user_order,
                                 :limit => 10,
                                 :offset => params[:offset].to_i)
      @available_projects = Project.active.all(:select => project_select,
                                               :order => project_order)
      @selected_projects = []
    else


      @project_billing_ids = [0] if @project_billing_ids.empty? and @billing != 0 and !@billing.nil?
      @project_type_ids = [0] if @project_type_ids.empty? and @projtype != 0 and @projtype != nil
      available_project_conditions = []
      available_project_conditions << ((@selected_acctype == 0) ? nil : "\"projects\".\"acctg_type\" = #{params[:acctype]}")
      available_project_conditions << ((params[:selectedprojects].blank?) ? nil : "id not in (#{params[:selectedprojects].join(',')})")
      available_project_conditions << ("id in (#{@project_billing_ids.join(',')})") if !@project_billing_ids.empty? and @billing != "0" and !@billing.nil?
      available_project_conditions << ("id in (#{@project_type_ids.join(',')})") if !@project_type_ids.empty? and @projtype != "0" and @projtype != ""
      available_project_conditions = available_project_conditions.compact.join(" and ")

      @available_projects = Project.active.all(:select => project_select,
                                               :conditions => available_project_conditions,
                                               :order => project_order)
      selected_project_conditions = ((params[:selectedprojects].blank?) ? "id is null" : "id in (#{params[:selectedprojects].join(',')})")
      @selected_projects = Project.active.all(:select => project_select,
                                              :conditions => selected_project_conditions,
                                              :order => project_order)
      selected_user_conditions = []
      selected_user_conditions << "\"users\".\"status\" = 1"
      selected_user_conditions << eng_only
      selected_user_conditions << ((@selected_projects.size > 0) ? "users.id in ( select m.user_id from members as m where m.project_id in( #{@selected_projects.collect(&:id).join(',')} ) )" : "id is null")
      selected_user_conditions = selected_user_conditions.compact.join(" and ")
      @selected_users = User.all(:select => user_select,
                                 :conditions => selected_user_conditions,
                                 :include => [:projects, {:memberships, :role}],
                                 :order => user_order,
                                 :limit => 10,
                                 :offset => params[:offset].to_i)

      available_user_conditions = []
      available_user_conditions << "\"users\".\"status\" = 1"
      available_user_conditions << eng_only
      available_user_conditions << ((@selected_users.size > 0) ? "id not in (#{@selected_users.collect(&:id).join(',')})" : nil)
      available_user_conditions = available_user_conditions.compact.join(" and ")
      @available_users = User.all(:select => user_select,
                                  :conditions => available_user_conditions,
                                  :order => user_order)
    end

    ####################SUMMARY COMPUTATION###################

    user_list = (@selected_users.size > 0) ? "time_entries.user_id in (#{@selected_users.collect(&:id).join(',')}) and" : ""
    project_list = (@selected_projects.size > 0) ? "time_entries.project_id in (#{@selected_projects.collect(&:id).join(',')}) and" : ""
    bounded_time_entries_billable = TimeEntry.find(:all,
                                                   :conditions => ["#{user_list} #{project_list} spent_on between ? and ? and issues.acctg_type = (select id from enumerations where name = 'Billable')",
                                                                   @from, @to],
                                                   :include => [:project],
                                                   :joins => [:issue],
                                                   :order => "projects.name asc")
    bounded_time_entries_billable.each { |v| v.billable = true }
    bounded_time_entries_non_billable = TimeEntry.find(:all,
                                                       :conditions => ["#{user_list} #{project_list} spent_on between ? and ? and issues.acctg_type = (select id from enumerations where name = 'Non-billable')",
                                                                       @from, @to],
                                                       :include => [:project],
                                                       :joins => [:issue],
                                                       :order => "projects.name asc")
    bounded_time_entries_non_billable.each { |v| v.billable = false }
    time_entries = TimeEntry.find(:all,
                                  :conditions => ["#{user_list} spent_on between ? and ?",
                                                  @from, @to])

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

    from, to = ((params[:from] && params[:to]) ? [@from, @to] : [(Date.today - 4.weeks), Date.today])
    project_ids = (@selected_projects.any? ? @selected_projects.collect(&:id) : @available_projects.collect(&:id))
    @selected_users.each do |usr|
      if usr.class.to_s == "User"
        b = bounded_time_entries_billable.select { |v| v.user_id == usr.id }
        nb = bounded_time_entries_non_billable.select { |v| v.user_id == usr.id }
        x = Hash.new

        x[:id] = usr.id
        x[:location] = usr.location
        x[:name] = usr.display_name
        x[:skill] = usr.skill
        x[:entries] = b + nb
        x[:total_hours] = time_entries.select { |v| v.user_id == usr.id }.collect(&:hours).compact.sum
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
    location = ((params[:location].eql?('N/A') or params[:location].blank?) ? nil : params[:location])
    skill = ((params[:skill].eql?('N/A') or params[:skill].blank?) ? nil : params[:skill])
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

  def compute_details(week, user, resources, acctg)
    from, to = week.first, week.last
    total_forecast = resources.sum { |a| a.capped_days_report((from..to), nil, false, acctg) }
    total_forecast_cost = resources.sum { |a| a.capped_cost_report((from..to), nil, false, acctg) }
    project_allocation = total_forecast * 8

    # available days and hours without weekends and holidays
    available_hours = user.available_hours(week.first, week.last, user.location)
    revenue = user.billable_revenue(week.first, week.last, user.location)
    available = available_hours/8

    if user.rate_histories && rate = user.rate_histories.detect { |v| v.effective_date && v.effective_date <= to && v.end_date && v.end_date >= from }
      default_rate = rate.default_rate
    elsif user.effective_date && from >= user.effective_date
      default_rate = user.default_rate
    else
      default_rate = 0
    end

    # available days and hours without weekends
    available_with_holidays = user.available_hours_with_holidays(week.first, week.last, user.location)/8
    available_hours_with_holidays = available_with_holidays * 8

    billable_hours = resources.collect { |mem| mem.spent_time(from, to, "Billable", true).to_f }.sum
    billable_cost = resources.collect { |mem| mem.spent_cost(from, to, "Billable").to_f }.sum

    @a["#{user.login}"] = {:lastname => user.lastname, :firstname => user.firstname, :skill => user.skill, :location => user.location,
                           :hired_date => user.hired_date, :end_date => user.resignation_date, :status => user.employee_status,
                           :available_with_holidays => available_with_holidays, :available_hours_with_holidays => available_hours_with_holidays,
                           :available_days => available, :available_hours => available_hours, :billable_hours => billable_hours,
                           :project_allocation => project_allocation, :allocation_cost => total_forecast_cost, :billed_amount => billable_cost,
                           :revenue => revenue, :default_rate => default_rate}

    @total_billable_revenue += revenue
    @total_billable_hours += billable_hours
    @billable_resources_count += 1 if available_hours > 0
    @total_forecasted_hours += project_allocation
    @total_available_hours += available_hours
    @total_available_hours_with_holidays += available_hours_with_holidays
  end

  def get_project_billing_details(project, from, to)
    bm = Project.find_by_id(project.id).billing_model

    members = project.members.sort_by { |x| [x.user.lastname, x.user.firstname] }
    total_allocated_hours, total_allocated_cost, total_actual_hours = 0.0, 0.0, 0.0
    total_billable_amount, total_billable_hours, total_actual_billable = 0.0, 0.0, 0.0

    members.each do |member|
      user = member.user
      h_date, r_date = to_date_safe(user.hired_date), to_date_safe(user.resignation_date)
      unless (h_date && h_date >= to) || (r_date && r_date <= from)
        if user.rate_histories && rate = user.rate_histories.detect { |v| v.effective_date && v.effective_date <= to && v.end_date && v.end_date >= from }
          default_rate = rate.default_rate
        elsif user.effective_date && from >= user.effective_date
          default_rate = user.default_rate
        else
          default_rate = 0
        end

        total_forecast, total_forecast_cost = 0.0, 0.0
        actual_hours, billable_amount = 0.0, 0.0
        res_alloc = member.resource_allocations.select { |alloc| alloc.start_date <= to && alloc.end_date >= from }
        if res_alloc && !res_alloc.empty?
          sow_rate = res_alloc.last.sow_rate ? res_alloc.last.sow_rate : 0.0
          total_allocated_hours += total_forecast += member.capped_days_report((from..to), nil, false, "billable") * 8
          total_allocated_cost += total_forecast_cost += member.capped_cost_report((from..to), nil, false, "billable")
          total_actual_hours += actual_hours += member.spent_time(from, to, "Billable", true).to_f + member.spent_time_on_admin(from, to, "Billable", true).to_f
          total_billable_amount += billable_amount += member.spent_cost(from, to, "Billable").to_f
          total_billable_hours += billable_hours = actual_hours
          total_actual_billable += actual_billable = billable_amount
          name = "#{user.lastname}, #{user.firstname}"

          if res_alloc && res_alloc.count > 1
            sow_count = res_alloc.select { |v| v.sow_rate && v.sow_rate > 0 }.count
            if sow_count && sow_count > 0
              alloc_array = ""
              old_rate = 0
              res_alloc.each do |v|
                start_date = v.start_date < from ? from : v.start_date
                end_date = v.end_date > to ? to : v.end_date
                unless old_rate == v.sow_rate
                  alloc_array += "#{v.sow_rate} (#{start_date.strftime("%m/%d")} - #{end_date.strftime("%m/%d")}) "
                else
                  alloc_array += "(#{start_date.strftime("%m/%d")} - #{end_date.strftime("%m/%d")}) "
                end
                old_rate = v.sow_rate
              end
              sow_rate = alloc_array
            else
              sow_rate = sow_rate
            end
          else
            sow_rate = sow_rate
          end
          @pb["#{member.id}"] = {:name => name, :default_rate => default_rate, :sow_rate => sow_rate,
                                 :allocated_hours => total_forecast, :allocated_cost => total_forecast_cost,
                                 :actual_hours => actual_hours, :billable_amount => billable_amount,
                                 :billable_hours => billable_hours, :actual_billable => actual_billable}

        end
      end
    end
    @per_project["#{project.id}"] = {:total_allocated_hours => total_allocated_hours,
                                     :total_allocated_cost => total_allocated_cost,
                                     :total_actual_hours => total_actual_hours,
                                     :total_billable_amount => total_billable_amount,
                                     :total_billable_hours => total_billable_hours,
                                     :total_actual_billable => total_actual_billable}
    @overall_forcasted_hours += total_allocated_hours
    @overall_actual_hours += total_actual_hours
  end

  def get_resource_billing_detail(user, beginning_of_month, end_of_month)
    h_date, r_date = to_date_safe(user.hired_date), to_date_safe(user.resignation_date)
    unless (h_date && h_date >= end_of_month) || (r_date && r_date <= beginning_of_month)
      members = user.members

      total_allocated_hours = 0.0
      total_allocated_cost = 0.0
      total_actual_hours = 0.0
      total_billable_amount = 0.0
      total_billable_hours = 0.0
      total_actual_billable = 0.0

      members.each do |member|
        bm = member.project.billing_model
        project = member.project
        total_forecast = 0.00
        total_forecast_cost = 0.00
        actual_hours = 0.0
        billable_amount = 0.0
        project_name = "#{project.name}: #{bm}"
        res_alloc = member.resource_allocations.select { |alloc| alloc.start_date <= end_of_month && alloc.end_date >= beginning_of_month }
        if res_alloc && !res_alloc.empty?
          sow_rate = res_alloc.last.sow_rate ? res_alloc.last.sow_rate : 0.0
          total_allocated_hours += total_forecast += member.capped_days_report((beginning_of_month..end_of_month), nil, false, "billable") * 8
          total_allocated_cost += total_forecast_cost += member.capped_cost_report((beginning_of_month..end_of_month), nil, false, "billable")
          total_actual_hours += actual_hours += member.spent_time(beginning_of_month, end_of_month, "Billable", true).to_f + member.spent_time_on_admin(beginning_of_month, end_of_month, "Billable", true).to_f
          total_billable_amount += billable_amount += member.spent_cost(beginning_of_month, end_of_month, "Billable").to_f
          total_billable_hours += billable_hours = actual_hours
          total_actual_billable += actual_billable = billable_amount
          if res_alloc && res_alloc.count > 1
            sow_count = res_alloc.select { |v| v.sow_rate && v.sow_rate > 0 }.count
            if sow_count > 0
              alloc_array = ""
              old_rate = 0
              res_alloc.each do |v|
                start_date = v.start_date < beginning_of_month ? beginning_of_month : v.start_date
                end_date = v.end_date > end_of_month ? end_of_month : v.end_date
                unless old_rate == v.sow_rate
                  alloc_array += "#{v.sow_rate} (#{start_date.strftime("%m/%d")} - #{end_date.strftime("%m/%d")}) "
                else
                  alloc_array += "(#{start_date.strftime("%m/%d")} - #{end_date.strftime("%m/%d")}) "
                end
                old_rate = v.sow_rate
              end
              sow_rate = alloc_array
            else
              sow_rate = sow_rate
            end
          else
            sow_rate = sow_rate
          end
        end
        @rb["#{member.id}"] = {:project => project_name, :sow_rate => sow_rate, :allocated_hours => total_forecast,
                               :allocated_cost => total_forecast_cost, :actual_hours => actual_hours,
                               :billable_amount => billable_amount, :billable_hours => billable_hours,
                               :actual_billable => actual_billable}
      end

      @per_user["#{user.id}"] = {:total_allocated_hours => total_allocated_hours,
                                 :total_allocated_cost => total_allocated_cost,
                                 :total_actual_hours => total_actual_hours,
                                 :total_billable_amount => total_billable_amount,
                                 :total_billable_hours => total_billable_hours,
                                 :total_actual_billable => total_actual_billable}

      @overall_forcasted_hours += total_allocated_hours
      @overall_actual_hours += total_actual_hours
    end
  end

  def get_project_billing_details_weekly(project, from, to)
    weeks = get_weeks_range(@beginning_of_month, @end_of_month)

    members = project.members.sort_by { |x| [x.user.lastname, x.user.firstname] }

    members.each do |member|
      user = member.user
      h_date, r_date = to_date_safe(user.hired_date), to_date_safe(user.resignation_date)
      unless (h_date && h_date >= to) || (r_date && r_date <= from)
        @pb["#{member.id}"] = {:name => "#{user.lastname}, #{user.firstname}"}
        weeks.each do |week|
          total_forecast = 0.00
          actual_hours = 0.0
          res_alloc = member.resource_allocations.select { |alloc| alloc.start_date <= week.last && alloc.end_date >= week.first }
          if res_alloc && !res_alloc.empty?
            total_forecast += member.capped_days_weekly_report((week.first..week.last), nil, false) * 8
            actual_hours += member.spent_time(week.first, week.last, nil, true).to_f + member.spent_time_on_admin(week.first, week.last, nil, true).to_f
          end
          @pb["#{member.id}"]["allocated_hours_#{week.last}"] = total_forecast
          @pb["#{member.id}"]["actual_hours_#{week.last}"] = actual_hours
        end
      end

    end
  end


  def detect_holidays_in_week(location, week)
    locations = [6]
    locations << location if location
    locations << 3 if location.eql?(1) || location.eql?(2)
    Holiday.count(:all, :conditions => ["event_date > ? and event_date < ? and location in (#{locations.join(', ')})", week.first, week.last])
  end
end
