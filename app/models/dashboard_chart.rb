class DashboardChart
  attr_accessor :week_range, :categories, :resources
  
  def initialize(attrs)
    self.week_range = get_weeks_range
    if attrs
      self.categories = attrs[:categories]
      self.resources = attrs[:resources]
    end
  end
  
  def json_weeks_allocations
    data = {}
    if categories && resources
      categories.each {|category| data[category] = Array.new}
      week_range.each do |week|
        categories.each do |category|
          total_allocation = 0
          resources.select{|m| m.project.category.eql?(category)}.each {|r| total_allocation += r.days_and_cost(week)}
          data[category] << [week.first.end_of_week, total_allocation.to_f/5]
        end
      end
    end
    jdata = []
    data.each {|k,v| jdata << v}
    jdata.to_json
  end
  
  private
  def get_weeks_range(from=(Date.today-1.month), to=(Date.today + 6.months))
    if from && to
      weeks = []
      for i in 0 .. (from.weeks_ago(to)) do
        mon, fri = from.monday, from.monday + 4.days
        weeks << (mon .. fri)
        from = mon + 1.week
      end
      weeks
    end
  end
end
