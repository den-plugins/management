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

end
