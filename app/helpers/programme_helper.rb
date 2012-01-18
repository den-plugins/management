module ProgrammeHelper

  def color_code_for_category(project)
    pcode = project.for_time_logging_only? ? "vlgray" : ""
    pcode = "lgray" if project.category.eql?("Internal Project")
    pcode
  end
  
  def color_code_for_cost_status(project)
    return "not-applicable" if project.category.eql?("Internal Project")
    if project.planned_start_date && project.planned_start_date
      if display_by_billing_model(project).eql?("fixed")
        range = project.planned_start_date..project.planned_end_date
        contracts_amount = project.project_contracts.all.sum(&:amount)
        resources = project.members.all
        bac = resources.sum {|a| a.days_and_cost(range, daily_rate(a.internal_rate), false).last}
        total_budget = bac.to_f + (bac.to_f * (project.contingency.to_f/100))
        
        case contracts_amount <=> total_budget
          when -1; "red"
          when  1: "green"
          when  0: "yellow"
        end
      elsif display_by_billing_model(project).eql?("billability")
        if percent = (@billabilities[project.id] ? @billabilities[project.id]["total_percent_billability_week"] : nil)
          case
            when percent > 85; "green"
            when (80 ... 85) === percent; "yellow"
            when (0 ... 80) === percent; "red"
          end
        else
          "nocolor"
        end
      end
    else
      "nocolor"
    end
  end
  
  def color_code_for_issue_average(project)
    issue_ave = PmDashboardIssue.average(:impact, :conditions => ["project_id = ? AND date_close IS NULL", project])
    case issue_ave.to_f.ceil
    when 0; "green"
    when 1; "green"
    when 2; "yellow"
    when 3; "red"
    end
  end
  
  def color_code_for_risk_average(project)
    risk_ave = Risk.average(:final_risk_rating, :conditions => ["project_id = ? AND status <> 'C'", project])
    case risk_ave.to_f.ceil
      when 0 ... 5; "green"
      when 5 ... 15; "yellow"
      when 15 .. 25; "red"
    end
  end
  
  def color_code_for_schedule_status(project)
    if project.planned_start_date && project.planned_start_date
      if project.actual_end_date
        (project.actual_end_date < project.planned_end_date) ? "red" : "green"
      else
        "yellow"
      end
    else
      "nocolor"
    end
  end
  
  def daily_rate(rate)
    rate.to_f * 8
  end
  
  def display_by_billing_model(project)
    if project.billing_model
      if project.billing_model.scan(/^(Fixed)/).flatten.present?
        "fixed"
      elsif project.billing_model.scan(/^(T and M)/i).flatten.present?
        "billability"
      end
    end
  end
  
  def initials(first, last)
    [first, last].map {|c| c.chars.first.upcase } if first && last
  end

  def get_min_date(projects)
    min_date = (projects.map(&:planned_end_date) | projects.map(&:actual_end_date)).compact.min {|a,b| a <=> b}
    min_date = (min_date ? (min_date - 2.months) : nil)
  end

  def sched_chart_data(projects, min_date)
    scheduled, planned = [], []
    projects.each do |project|
      pname = sub_name(project.name.to_s)
      scheduled << (project.actual_end_date ? [project.actual_end_date.to_s, pname] : [min_date, pname])
      planned << (project.planned_end_date ? [project.planned_end_date.to_s, pname] : [min_date, pname])
    end
    [scheduled.reverse, planned.reverse].to_json
  end

  def sub_name(name)
    name.sub(/development/i, "").strip
  end
end
