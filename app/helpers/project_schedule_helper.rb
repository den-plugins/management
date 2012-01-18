module ProjectScheduleHelper

  def get_min_date(projects)
    min_date = (projects.map(&:planned_end_date) | projects.map(&:actual_end_date)).compact.min {|a,b| a <=> b}
    min_date = (min_date ? (min_date - 2.months) : nil)
  end

  def chart_data(projects, min_date)
    scheduled, planned = [], []
    projects.each do |project|
      pname = sub_name(project.name.to_s)
      scheduled << (project.actual_end_date ? [project.actual_end_date.to_s, pname] : [min_date, pname])
      planned << (project.planned_end_date ? [project.planned_end_date.to_s, pname] : [min_date, pname])
    end
    [scheduled, planned].to_json
  end

  def sub_name(name)
    name.sub(/development/i, "").strip
  end

end
