module ResourceManagementsHelper

  def get_weeks_range(from, to)
    if from && to
      weeks = []
      for i in 0 .. (from.weeks_ago(to)) do
        mon, fri = from.monday, (from.monday + 4.days)
        weeks << (mon .. fri)
        from = mon + 1.week
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
    "%0.2f" % num
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
    skill_name = []
    counter = 0
    user.each do |u|
      unless u.is_resigned
        unless u.skill.nil?
          skill_name[counter] = u.skill
          counter += 1
        end
      end
    end
    ary = skill_name.uniq{|sname| s}
    ctr = 0
    ary.each do |q|
     num = skill_name.count q.to_s
     skill_set[ctr] = [q,num]
     ctr += 1
    end
    return skill_set.to_json
  end
  
  def count_billabilty_skill(set, users, projects)
    projects = projects.collect {|p| p.id if (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable'))}
    users = users.reject do |user|
      user.members.select {|m| m.project.active? && projects.include?(m.project.id)}.empty?
    end
    
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
      user.members.select {|m| m.project.active? && projects.include?(m.project.id)}.empty?
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
    resource_count.sort.each {|r, v| jdata << v }
    jdata.to_json
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
      user.members.select {|m| m.project.active? && projects.include?(m.project.id)}.empty?
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
     res_billability_forecast << [week.last.to_s, total_allocated_percent.round(2)] 
    end 
    return res_billability_forecast.to_json
  end

  def resource_forecast_summary(resources, projects, skill_set, accounting, total_res_available)
    str = ""
    start_date, end_date = Date.today - 1.month, Date.today + 6.months
    weeks = get_weeks_range(start_date, end_date)
    total_days = 0
    resource_count = {}
    res_count_per_work_days = 0.0
    res_allocations_skill = {}
    str += "<div id='floating_tables_holder' style='width: #{weeks.count * 85}px'>"
      weeks.each do |week|
        total_days = week.count
        weekly_resources_count = 0
        str += "<div class='floating_table'>
          <table id='allocation_week' class='list fixed'>
            <tr>
                <th>#{display_week(week)}</th>
            </tr>"
            resources.each do |resource|
                res_allocations = resource.allocations(week, projects)
                res_allocations_skill[resource.skill] = 0 if res_allocations_skill[resource.skill].nil?
                resource_count[resource.skill] = 0 if resource_count[resource.skill].nil?
                str += "<tr class='#{cycle('even', 'odd', :name => 'week_days')} #{allocation_to_class(res_allocations)}'>"
                str += "<td>#{res_allocations}</td>"
                res_allocations_skill[resource.skill] += res_allocations if !resource.is_resigned
                resource_count[resource.skill] += 1 if !res_allocations.zero? and !resource.is_resigned
              str += "</tr>"
              weekly_resources_count += 1
            end
            reset_cycle('week_days')
            current_total_res_available = 0
            str += "<tr><th>&nbsp;</th></tr>"
            skill_set.each do |skill|
              str += "<tr style='background-color: #eee;'>"
              resource_count[skill] = 0 if resource_count[skill].nil?
              resource_count[skill] += resource_countby(skill, week, accounting)
              str += "<td>#{resource_count[skill]}</td>"
              current_total_res_available += resource_count[skill] ? resource_count[skill] : 0.0
              resource_count[skill] = 0
              str += "</tr>"
            end
            str += "<tr style='background-color: #eee;'><td>&nbsp;</td></tr>
            <tr style='background-color: #eee;'>
              <td>#{current_total_res_available}</td>
            </tr>"
            percent_allocated = (get_float(current_total_res_available) / get_float(total_res_available)) * 100
            percent_unallocated = (get_float(total_res_available - current_total_res_available) / get_float(total_res_available)) * 100
            str += "<tr style='background-color: #eee;'><td>#{get_string(percent_unallocated.round(2))}%</td></tr>
            <tr style='background-color: #eee;'><td>#{get_string(percent_allocated.round(2))}%</td></tr>
            <tr><th>#{total_days}</th></tr>"
            current_res_allocated = 0.0
            skill_set.each do |skill|
              str += "<tr style='background-color: #eee;'>"
                res_allocations_skill[skill] = 0 if res_allocations_skill[skill].nil?
                res_allocations_skill[skill] += get_total_allocations_per_skill(skill, week, accounting)
                res_count_per_work_days = res_allocations_skill[skill] ? (get_float(res_allocations_skill[skill])/get_float(total_days)) : 0.0
                str += "<td>#{get_string(res_count_per_work_days)}</td>"
                current_res_allocated += res_count_per_work_days
                res_allocations_skill[skill] = 0.0
              str += "</tr>"
            end
            str += "<tr style='background-color: #eee;'><td>&nbsp;</td></tr>
            <tr style='background-color: #eee;'><td>#{get_string(current_res_allocated.round(2))}</td></tr>
            <tr style='background-color: #eee;'><td>#{get_string(weekly_resources_count)}</td></tr>"
            total_allocated_percent = (current_res_allocated / get_float(weekly_resources_count)) * 100
            str += "<tr style='background-color: #eee;'><td>#{get_string(total_allocated_percent.round(2))}%</td></tr>
          </table>
        </div>"
      end
      str += "</div>"
  end
  
  def allocation_to_class(allocation)
    case allocation
      when 0; ""
      when 0 .. 2.5; "lblue"
      when 2.5 .. 5; "lgreen"
      else; "lred"
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

end
