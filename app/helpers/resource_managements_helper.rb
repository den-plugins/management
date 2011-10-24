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
  
  def acronym(name)
    name.sub('-', ' ').split.collect {|word| word.chars.first.upcase}.to_s if name
  end
end
