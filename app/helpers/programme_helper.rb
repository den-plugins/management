module ProgrammeHelper

  def code_by_budget_and_forecast(budget, forecast)
    if budget && forecast
      case budget <=> forecast
        when -1; "tred"
        when  1: "green"
        when  0: "yellow"
      end
    end
  end

  def code_by_billability_rate(percent)
    if percent
      case
        when percent > 88; "green"
        when (85 ... 88) === percent; "yellow"
        when (0 ... 85) === percent; "red"
      end
    end
  end

  def color_code_for_category(project)
    pcode = project.for_time_logging_only? ? "vlgray" : ""
    pcode = "lgray" if project.category.eql?("Internal Project")
    pcode = "closed" if project.closed?
    pcode
  end

  def color_code_for_cost_status(project)
    return "not-applicable" if project.category.eql?("Internal Project")
    if project.planned_start_date && project.planned_start_date
      if display_by_billing_model(project).eql?("fixed")
        puts "project : #{project}"
        project_id = "fixed_cost_#{project.id}"
        puts "project_id : #{project_id}"
        budget = (@fixed_costs[project_id] ? @fixed_costs[project_id]["cost_budget"] : nil)
        forecast = (@fixed_costs[project_id] ? @fixed_costs[project_id]["cost_forecast"] : nil)
        puts "budget : #{budget}"
        puts "forecast : #{forecast}"
        code = code_by_budget_and_forecast(budget, forecast) || "nocolor"
      elsif display_by_billing_model(project).eql?("billability")
        project_id = "billability_#{project.id}"
        percent = (@billabilities[project_id] ? @billabilities[project_id]["total_percent_billability_week"] : nil)
        code = code_by_billability_rate(percent) || "nocolor"
      end
    else
      code = "nocolor"
    end
    code
  end
  
  def color_code_for_contract_status(project)
    # Get Project Contract Status
    project_contract = ProjectContract.find(:first, :conditions => "project_id = #{project}", :order => "effective_to DESC")
    
    if project_contract
      effective_date = project_contract.effective_to
      project_contract_status = project_contract.contract_status
      contract_about_to_expire_in_two_weeks = (effective_date + 14.days) if effective_date
    end
    
    if effective_date.nil?
      contract_status_color_code = 'nocolor'
    else
      if (project_contract_status == 1 && Date.today < effective_date)
        contract_status_color_code = 'green'
      elsif (project_contract_status ==1 && (contract_about_to_expire_in_two_weeks && (contract_about_to_expire_in_two_weeks == Date.today)))
        contract_status_color_code = 'yellow'
      elsif (Date.today > effective_date && project_contract_status == 1)
        contract_status_color_code = 'red'
      elsif (project_contract_status == 2)      
        contract_status_color_code = 'nocolor'
      end
    end
    
    contract_status_color_code
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
    if project.is_a?(Project)
      start_date, end_date = project.planned_start_date, project.planned_end_date
      actual_end_date = project.actual_end_date
    elsif project.is_a?(Issue)
      start_date, end_date = project.start_date, project.due_date
      actual_end_date = Date.today
    end
    color = "nocolor"
    if start_date && end_date
      if actual_end_date
        if project.is_a?(Project)
          color = (actual_end_date > end_date ? "red" : "green")
        elsif project.is_a?(Issue)
          color = (actual_end_date > end_date && !project.closed? ? "red" : "green")
        end
      else
        color = "yellow"
      end
    end
    return color
  end

  def color_code_for_billability(project)
    return "not-applicable" if project.category.eql?("Internal Project") || display_by_billing_model(project).eql?("fixed")
    if project.planned_start_date
        project_id = "billability_#{project.id}"
        billability = (@billabilities[project_id] ? @billabilities[project_id]["total_percent_billability_week"] : 0)
        if billability < 85
          code = "red"
        elsif billability >= 85 && billability < 88
          code = "yellow"
        else
          code = "green"
        end
    else
      code = "nocolor"
    end
    code
  end

  def color_code_for_warranty(project)
    project.in_warranty? ? "warrantied" : ""
  end

  def color_code_for_project_resourcing_state(issue)
    value = pre_sales_custom_field(issue, 'Project Resourcing State')
    value.blank? ? 'nocolor' : value.downcase
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

  def get_min_date(projects)
    min_date = (projects.map(&:planned_end_date) | projects.map(&:actual_end_date)).compact.min {|a,b| a <=> b}
    min_date = (min_date ? (min_date - 2.months) : nil)
  end

  def initials(first, last)
    [first, last].map {|c| c.chars.first.upcase } if first && last
  end

  def jsoned_billability_percentage(projects, bill)
    ticks = []
    data = []
    projects.each do |project|
      id = "billability_#{project.id}"
      percent = bill[id] ? bill[id]["total_percent_billability_week"] : nil
      if project.closed?
        ticks << sub_name("***" + project.name)
      else
        ticks << sub_name(project.name)
      end
      data << percent
    end
    [ticks.to_json, data.to_json]
  end

  def sched_chart_data(projects, min_date)
    scheduled, planned = [], []
    projects.each do |project|
      pname = project.closed? ? sub_name("*** " + project.name.to_s) : sub_name(project.name.to_s)
      scheduled << (project.actual_end_date ? [project.actual_end_date.to_s, pname] : [min_date, pname])
      planned << (project.planned_end_date ? [project.planned_end_date.to_s, pname] : [min_date, pname])
    end
    [scheduled.reverse, planned.reverse].to_json
  end

  def sched_chart_data_with_maintenance(projects, min_date)
    scheduled, planned, maintenance = [], [], []
    projects.each do |project|
      pname = project.closed? ? sub_name("*** " + project.name.to_s) : sub_name(project.name.to_s)
      scheduled << (project.actual_end_date ? [project.actual_end_date.to_s, pname] : [min_date, pname])
      planned << (project.planned_end_date ? [project.planned_end_date.to_s, pname] : [min_date, pname])
      maintenance << (project.maintenance_end ? [project.maintenance_end.to_s, pname] : [min_date, pname])
    end
    [maintenance.reverse, scheduled.reverse, planned.reverse].to_json
  end


  def fixed_cost_projects_chart_data(projects, fixed_costs)
    data, ticks = [], []
    baselines, actuals, forecasts = [], [], []
    projects.each do |project|
      if project.closed?
        ticks << sub_name("***" + project.name)
      else
        ticks << sub_name(project.name)
      end
      fixed_cost = fixed_costs["fixed_cost_#{project.id}"] ? fixed_costs["fixed_cost_#{project.id}"] : {}
      baselines << fixed_cost["cost_budget"]
      actuals << fixed_cost["cost_actual"]
      forecasts << fixed_cost["cost_forecast"]
    end
    data = [baselines, actuals, forecasts]
    return [ticks.to_json, data.to_json]
  end

  def sub_name(name)
    name.sub(/development/i, "").strip
  end

  def pre_sales_custom_field_names
    project = Project.find_by_name 'Exist Pre-Sales'
    fields = IssueCustomField.all.select { |f| f.project_ids.include?(project.id) }
    fields.map(&:name)
  end

  def pre_sales_custom_field(issue, field_name)
    if pre_sales_custom_field_names.include?(field_name)
      if custom_value = issue.custom_values.detect{ |v| v.custom_field.name == field_name }
        custom_value.value
      end
    end
  end

  def user_name(user_id)
    user = User.find(user_id)
    "#{user.firstname} #{user.lastname}"
  end
end
