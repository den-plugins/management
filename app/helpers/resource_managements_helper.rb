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
    projects = projects.collect {|p| p.id if (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable'))}

    reports, totals = [], []
    report_date =  (Date.today - 1.week).monday
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
    projects = projects.collect {|p| p.id if (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable'))}
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
    total_days = 0
    resource_count = {}
    res_count_per_work_days = 0.0
    res_allocations_skill = {}
    res_billability_forecast = []
    projects = @projects.collect {|p| p.id if (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable'))}
    users = @users.reject do |user|
      user.members.select {|m| projects.include?(m.project.id)}.empty?
    end
    weeks.each do |week|
     total_days = week.count
     weekly_resources_count = 0
     users.each do |resource|
       res_allocations = resource.allocations(week, projects)
       res_allocations_skill[resource.skill] = 0 if res_allocations_skill[resource.skill].nil?
       resource_count[resource.skill] = 0 if resource_count[resource.skill].nil?
       res_allocations_skill[resource.skill] += res_allocations if !resource.is_resigned
       resource_count[resource.skill] += 1 if !res_allocations.zero? and !resource.is_resigned
       weekly_resources_count += 1
     end
     current_res_allocated = 0.0
     @skill_set.each do |skill|
       res_allocations_skill[skill] = 0 if res_allocations_skill[skill].nil?
       res_allocations_skill[skill] += get_total_allocations_per_skill(skill, week, nil)
       res_count_per_work_days = res_allocations_skill[skill] ? (get_float(res_allocations_skill[skill])/get_float( total_days)) : 0.0
       current_res_allocated += res_count_per_work_days
       res_allocations_skill[skill] = 0.0
     end
     total_allocated_percent = weekly_resources_count != 0 ? (current_res_allocated / get_float(weekly_resources_count)) * 100 : 0.0
     res_billability_forecast << [week.last, total_allocated_percent.round(2)]
    end
    return res_billability_forecast.to_json
  end

  def forecast_billable_data(users, range)
    data, ticks, number_of_users = [], [], []
    available, forecast, billable = [], [], []
    months = get_months_range(range.first, range.last)
    months.each do |m|
      tmp_availables, tmp_forecasts, tmp_billables = [], [], []
      user_count = 0
      users.each do |u|
        r = u.custom_values.detect {|v| v.mgt_custom "Employment End"}
        d = (r.nil? or r.value == "") ? nil : Date.parse(r.value)
        unless d and ((m.first..m.last) === d || m.last > d)
          user_count += 1
          tmp_availables << u.available_hours(m.first, m.last, u.location)
          tmp_forecasts << cost_compute_forecasted_hours_with_capped_allocation(m, u.members.all, "billable")
          tmp_billables << u.members.all.collect { |mem| mem.spent_time(m.first, m.last, "Billable", true).to_f }.sum
        end
      end
      number_of_users << user_count
      ticks << m.first.strftime("%b %Y #{number_of_users}")
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
        when 0 .. 2.5; "lblue"
        when 2.5 .. 5; "lgreen"
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
    elsif user.registered?
      link_to l(:button_activate), url.merge(:user => {:status => User::STATUS_ACTIVE}), :method => :post, :class => 'icon icon-unlock'
    elsif user != User.current
      link_to l(:button_lock), url.merge(:user => {:status => User::STATUS_LOCKED}), :method => :post, :class => 'icon icon-lock'
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
        with_complete_logs += 1 if m[:total_hours_on_selected] >= m[:forecasted_hours_on_selected]
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
    "lred" if user[:total_hours].to_f < user[:forecasted_hours_on_selected].to_f
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

end
