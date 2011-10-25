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
    return proj_categories.possible_values
  end

  def set_categories_count(categories)
    temp = {}
    categories.each do |category|
      temp[category] = 0
    end
    temp[""] = 0
    return temp
  end
  
  def acronym(name)
    name.sub('-', ' ').split.collect {|word| word.chars.first.upcase}.to_s if name
  end

  def get_float(num)
    ("%.2f" % num).to_f
  end
end
