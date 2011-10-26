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

  def project_categories
    proj_categories = CustomField.find(:first, :conditions => "type = 'ProjectCustomField' and name = 'Category'")
    return (proj_categories.nil? ? [] : proj_categories.possible_values)
  end

  def resource_skills
    res_skills = CustomField.find(:first, :conditions => "type = 'UserCustomField' and name = 'Skill or Role'")
    return (res_skills.nil? ? [] : res_skills.possible_values)
  end

  def set_categories_count(categories)
    temp = {}
    categories.each do |category|
      temp[category] = 0
    end
    temp[""] = 0
    return temp
  end

  def resource_countby(skill, week=nil)
    unless week
      @resources_no_limit.select {|r| r.skill == skill and !r.is_resigned}.count
    else
      @resources_no_limit.select {|r| r.skill == skill and !r.is_resigned and !r.allocations(week).to_f.zero?}.count
    end
  end

  def count_resigned
    @resources_no_limit.select {|r| r.is_resigned}.count
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
end
