module ResourceManagementsHelper

  def get_weeks_range(from, to)
    if from && to
      start_date, end_date = from, to
      weeks = []
      # if from/to falls on a weekend, mon/fri is set to self (date)
      until ((from..to).to_a & (start_date..end_date).to_a).empty?
        mon = if from.wday.eql?(0) || from.wday.eql?(6)
                       from
                     else
                       from.eql?(start_date) ? start_date : from.monday
                     end
        fri = if from.wday.eql?(0) || from.wday.eql?(6)
                   from
                 else
                   from.weeks_ago(to).eql?(0) ? to : (mon.monday+4.days)
                 end
        from = mon.next_week
        weeks << (mon .. fri)
      end
      weeks
    end
  end

  def display_week(range)
    from, to = range.first, range.last
    s = "%s/" % from.mon + "%s" % from.day + " - " +
           "%s/" % to.mon + "%s" % to.day
  end

  def set_categories_count(categories)
    temp = {}
    categories.each do |category|
      temp[category] = 0
    end
    temp[""] = 0
    return temp
  end

  def resource_countby(skill, week=nil, acctg=nil)
    if @resources_no_limit
      resources = @resources_no_limit - @resources
      if week.nil?
        resources.select {|r| r.skill == skill and !r.is_resigned}.count
      else
        resources.select {|r| r.skill == skill and !r.is_resigned and !r.allocations(week, @projects).zero?}.count
      end
    end
  end

  def get_total_allocations_per_skill(skill, week, acctg)
    total_alloc_per_skill = 0.0
    if @resources_no_limit
      resources = @resources_no_limit - @resources
      resources.each {|r| total_alloc_per_skill += r.allocations(week, @projects) if r.skill == skill and !r.is_resigned}
    end
    total_alloc_per_skill
  end

  def count_resigned
    if @resources_no_limit
      @resources_no_limit.select {|r| r.is_resigned}.count
    end
  end

  def acronym(name)
    name.sub('-', ' ').split.collect {|word| word.chars.first.upcase}.to_s if name
  end

  def get_string(num)
    "%0.2f" % num.to_f
  end

  def get_float(num)
    ("%.2f" % num).to_f
  end

  def monday_last_week(format)
     date = (Date.today - 1.week).monday
     h date.strftime(format)
  end

  def count_user_skill(user)
    skill_set = []
    counted_users = user.select { |u| !u.is_resigned && !u.skill.nil? }
    user_skills = counted_users.group_by(&:skill)
    user_skills.each do |skill, users|
      percentage = (users.count.to_f/counted_users.count * 100.0).round
      label = "#{skill}<br>#{percentage}% &bull; #{users.count}"
      skill_set << [label, users.count, skill]
    end

    skill_set
  end

  def count_billabilty_skill(set, users, projects)
    projects = projects.collect {|p| p.id if (p.accounting_type.eql?('Billable'))}

    reports, totals = [], []
    report_date =  (Date.today).monday
    week = report_date .. (report_date + 4.days)
    set.each do |skill|
      report_count, total_count = 0
      if skill_users = users.select {|u| u.skill.eql?(skill) && !u.is_resigned}
        skill_users.each {|u| report_count += u.allocations(week, projects)}
        total_count = skill_users.count
      end
      reports << [report_count.to_f/5, skill]
      totals << [total_count.to_i, skill]
    end if set.is_a? Array
    [reports, totals].to_json
  end

  def count_billabilty_skill_set(set, users, projects)
    projects = projects.collect {|p| p.id if (p.accounting_type.eql?('Billable'))}
    users = users.reject do |user|
      user.members.select {|m| projects.include?(m.project.id)}.empty?
    end

    weeks = get_weeks_range(Date.today - 1.month, Date.today + 6.months)
    resource_count = {}

    set.each do |skill|
      temp, resource_count[skill] = [], []
      if skill_users = users.select {|u| u.skill.eql?(skill) && !u.is_resigned}
        weeks.each do |week|
          report_count = 0
          skill_users.each {|u| report_count += u.allocations(week, projects)}
          temp = [week.last, report_count/5]
          resource_count[skill] << temp
        end
      end
    end if set.is_a? Array
    jdata = []
    jlabels = []
    resource_count.sort.each do |r, v|
      jdata << v
      jlabels << r
    end
    [jdata.to_json, jlabels]
  end

  def get_resource_billability_forecast
    start_date, end_date = Date.today - 1.month, Date.today + 6.months
    weeks = get_weeks_range(start_date, end_date)
    resource_count = {}
    res_allocations_skill = {}
    res_billability_forecast = []
    projects = @projects.collect {|p| p.id if (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable'))}
    users = @users.reject do |user|
      user.members.select {|m| projects.include?(m.project.id)}.empty?
    end
    weeks.each do |week|
     weekly_resources_count = 0
     users.each do |resource|

       resignation_date = to_date_safe(resource.resignation_date)
       hired_date = to_date_safe(resource.hired_date)
       start_date = hired_date && hired_date > week.first && hired_date < week.last ? hired_date : week.first
       end_date = resignation_date && resignation_date > week.first && resignation_date < week.last ? resignation_date : week.last
       total_working_days = (start_date..end_date).count
       working_days = 0
       alloc = resource.allocations(week, projects)

       project_allocations = resource.members.collect(&:resource_allocations).flatten.select do |v|
         @projects.include? v.member.project_id
       end
       if allocations = project_allocations.select {|a| a.start_date <= week.last && a.end_date >= week.first}.uniq
         allocations.each do |allocation|
           working_days = total_working_days - detect_holidays_in_week(allocation.location, week)
         end
       end
       skill = resource.skill
       res_allocations_skill[skill] ||= 0
       res_allocations_skill[skill] += alloc unless resource.is_resigned
       resource_count[skill] ||= 0
       resource_count[skill] += 1 if alloc.zero? && !resource.is_resigned || alloc < working_days && !resource.is_resigned

       if resignation_date && resignation_date > week.first && hired_date && hired_date < week.last
         weekly_resources_count += 1
       elsif !resignation_date && hired_date && hired_date < week.last
         weekly_resources_count += 1
       end

      end

      current_total_available_resources = 0         # current_total_res_available
      current_res_allocated = 0         # current_res_allocated

      @skill_set.each do |skill|
        current_total_available_resources += resource_count[skill].to_i
        resource_count_per_day = res_allocations_skill[skill].to_f/week.count.to_f
        current_res_allocated += resource_count_per_day
        resource_count[skill] = 0
        res_allocations_skill[skill] = 0.00
      end


      total_allocated_percent = weekly_resources_count != 0 ? (current_res_allocated / get_float(weekly_resources_count)) * 100 : 0.00
      res_billability_forecast << [week.last, total_allocated_percent]
    end
    return res_billability_forecast.to_json
  end
  
  def list_resource_names(users, range)
    list = {}
    months = get_months_range(range.first, range.last)
    months.each do |m|
      name = m.first.strftime("%b-%Y")
      list[:"#{name}"] = []
      users.each do |u|
        h_date, r_date = to_date_safe(u.hired_date), to_date_safe(u.resignation_date)
        unless (h_date && h_date > m.last) || (r_date && r_date < m.first)
          list[:"#{name}"] << u.id
        end
      end
    end
    return list
  end

  def forecast_billable_data(users, range)
    data, ticks = [], []
    available, forecast, billable = [], [], []
    months = get_months_range(range.first, range.last)
    months.each do |m|
      tmp_availables, tmp_forecasts, tmp_billables = [], [], []
      users.each do |u|
        h_date, r_date = to_date_safe(u.hired_date), to_date_safe(u.resignation_date)
        unless (h_date && h_date > m.last) || (r_date && r_date < m.first)
          tmp_availables << u.available_hours(m.first, m.last, u.location)
          tmp_forecasts << cost_compute_forecasted_hours_with_capped_allocation(m, u.members.all, "billable")
          tmp_billables << u.members.all.collect { |mem| mem.spent_time(m.first, m.last, "Billable", true).to_f }.sum
        end
      end
      ticks << m.first.strftime("%b %Y")
      available << tmp_availables.sum
      forecast << tmp_forecasts.sum
      billable << tmp_billables.sum
    end
    data = [forecast, billable, available]
    return [ticks, data]
  end

  def allocation_to_class(allocation, is_shadowed=false)
    if is_shadowed
      "lgray"
    else
      case allocation
        when 0; ""
        when 0 .. 0.5; "lblue"
        when 0.5 .. 1; "lgreen"
        else; "lred"
      end
    end
  end

  def mgt_custom_field_tag(name, params)
    custom_field = UserCustomField.find(:first, :conditions => ["name = ?", name])
    field_name = "filters[#{name.downcase.gsub(/ /,'_')}]"
    value = params[:filters] ? (params[:filters][name.downcase.gsub(/ /,'_').to_sym] || "") : ""

    case custom_field.field_format
    when "text"
      label_tag(field_name, name) + text_field_tag(field_name, nil, :rows => 3, :value => value)
    when "list"
      blank_option = "<option></option>"
      label_tag(field_name, name) + select_tag(field_name, blank_option + options_for_select(custom_field.possible_values, value))
    when "bool"
      label_tag(field_name, name) + check_box_tag(field_name, value, (value.to_i.eql?(1) ? true : false)) + hidden_field_tag(field_name, '0')
    end
  end

  def mgt_field_tag(label, field, params, options={})
    label = (label.nil? || label.blank?) ? nil : label
    field_name = "filters[#{field.downcase.gsub(/ /,'_')}]"
    value = params[:filters] ? (params[:filters][field.downcase.gsub(/ /, '_').to_sym] || "") : ""
    value = params[:filters] ? (params[:filters][field.downcase.gsub(/ /, '_').to_sym] || "") : "1" if field.to_s == "is_employed"

    case options[:format]
    when "text"
      label_tag(field_name, label) + text_field_tag(field_name, nil, :rows => 3, :value => value)
    when "list"
      blank_option = "<option></option>"
      label_tag(field_name, label) + select_tag(field_name, blank_option + options_for_select(options[:select_from], value))
    when "bool"
      label_tag(field_name, label) + check_box_tag(field_name, '1', (value.to_i.eql?(1) ? true : false)) + hidden_field_tag(field_name, '0')
    end
  end

  def update_status_link(user)
    url = {:action => 'edit_user', :id => user, :filters => params[:filters]}

    if user.locked?
      link_to l(:button_unlock), url.merge(:user => {:status => User::STATUS_ACTIVE}), :method => :post, :class => 'icon icon-unlock'
    elsif user.archived?
      link_to l(:button_unarchive), url.merge(:user => {:status => User::STATUS_ACTIVE}), :method => :post, :class => 'icon icon-unlock small'
    elsif user.registered?
      link_to l(:button_activate), url.merge(:user => {:status => User::STATUS_ACTIVE}), :method => :post, :class => 'icon icon-unlock'
    elsif user != User.current
      #link_to l(:button_lock), url.merge(:user => {:status => User::STATUS_LOCKED}), :method => :post, :class => 'icon icon-lock'
      link_to(l(:button_archive), url.merge(:user => {:status => User::STATUS_ARCHIVED}), :method => :post, :class => 'icon icon-lock small')
    end
  end

  def to_yml(string)
    if string.is_a? Date
      string.strftime("%m/%d/%Y")
    elsif string.is_a? String
      string.gsub(/ /, '_')
    end
  end

  def compute_percentage_utilization(members, from, to)
    with_complete_logs = 0
    if from && to && !members.empty?
      members.each do |m|
        with_complete_logs += 1 if m[:total_hours] >= m[:forecasted_hours_on_selected]
      end
    end
    (with_complete_logs.to_f / members.count.to_f) * 100
  end

  def get_acctg(acctg)
    case acctg
      when "both"; nil
      when "billable"; "Billable"
      when "non_billable"; "Non-billable"
    end
  end

  def actual_hours_on_memberships(user, range, acctg, projects = [])
    ah = 0
    if projects.any?
      memberships = user.memberships.find(:all,
                                          :conditions => ["project_id IN (#{projects.collect(&:id).compact.join(',')})"])
    else
      memberships = user.memberships
    end
    memberships.each do |m|
      acctg_type = get_acctg(acctg)
      ah += m.spent_time(range.first, range.last, acctg_type, true)
    end
    ah.to_f
  end

  def color_code_log_time(user)
    "lred" if user[:total_hours].to_f.round(2) < user[:forecasted_hours_on_selected].to_f
  end
  
  def class_of_resignation(user)
    user.is_resigned ? "resigned" : nil
  end

  def link_to_zoomed_chart(chart_name, options={})
    link = link_to('zoom', '#', options.merge(:id => "zoom_#{chart_name}", :class => 'zoom', :title => 'Zoom'))
    content_tag(:div, link, :style => 'overflow: hidden')
  end

  def to_date_safe(date)
    begin
      Date.parse date
    rescue
      nil
    end
  end

  def round_up(number)
    divisor = 10**Math.log10(number).floor
    i = number / divisor
    remainder = number % divisor
    if remainder == 0
      i * divisor
    else
      (i + 1) * divisor
    end
  end

  def date_filter_index(selection)
    case selection
      when "last week"
        0
      when "all time"
        1
      when "today"
        2
      when "yesterday"
        3
      when "this week"
        4
      when "this month"
        5
      when "last 7 days"
        6
      when "last month"
        7
      when "last 30 days"
        8
      when "this year"
        9
    end
  end

  def get_date_range(param_selection, param_from, param_to, param_is_employed)

    unless param_from.nil? || param_to.nil? || param_from.empty? || param_to.empty?
          from, to = param_from, param_to
    else
        selection = param_is_employed && !param_is_employed.blank? && param_selection ? param_selection : ""
          today = Date.today
           case selection
             when "last week"
                from = today - 7 - (today.cwday - 1)%7
                to = from + 6
             when "all time"
                from ||= (TimeEntry.minimum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_time_entries)) || today) - 1
                to   ||= (TimeEntry.maximum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_time_entries)) || today)
             when "today"
                from = to = today
             when "yesterday"
                from = to = today - 1
             when "this week"
                from = today - (today.cwday - 1)%7
                to = from + 6
             when "this month"
                from, to = today.beginning_of_month, today.end_of_month
             when "last 7 days"
                from = today - 7
                to = today
             when "last month"
                from, to = (today - 1.month).beginning_of_month, (today - 1.month).end_of_month
             when "last 30 days"
                from = today - 30
                to = today
             when "this year"
                from, to = today.beginning_of_year, (today - 1.month).end_of_month
             else
               from, to = today-1.months, today+6.months
           end
    end
    return from, to
  end

  def work_day_in_a_week(week)
    default = week.count
    week.each do |d|
      default -= 1 if Holiday.find_by_event_date(d.strftime.to_s)
    end
    default
  end

  def resigned_engineers(engineers,week)
    r_engrs = 0
    engineers.each do |x|
      if x.resignation_date != '' && x.resignation_date < week
        r_engrs += 1
      end
    end
    r_engrs
  end

end
