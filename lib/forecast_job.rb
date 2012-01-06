class ForecastJob < Struct.new(:accounting, :resources, :skill_set, :projects, :total_available_resources)
  include ResourceManagementsHelper
  
  def perform
    mgt = FileTest.exists?("#{RAILS_ROOT}/config/rm_forecasts.yml") ? YAML.load(File.open("#{RAILS_ROOT}/config/rm_forecasts.yml")) : {}
    
    forecasts, summary = {}, {}
    updated_at = Time.now

    resource_count = {}                   # total no. of resources per skill
    skill_allocations = {}                  # total allocation per skill (res_allocations_skill)
    
    weeks = get_weeks_range(Date.today-1.month, Date.today+6.months)
    weeks.each do |week|
      weekly_resources_count = 0
      forecasts_this_week = forecasts[to_yml(week.last)] || {}
      summary_this_week = summary[to_yml(week.last)] || {}
      summary_this_week["resource_count"] = {}
      summary_this_week["resource_count_per_day"] = {}

      resources.each do |r|
        resource = User.find(r)
        alloc = resource.allocations(week, projects)
        skill = resource.skill
        skill_allocations[skill] ||= 0
        skill_allocations[skill] += alloc unless resource.is_resigned
        resource_count[skill] ||= 0
        resource_count[skill] += 1 if !alloc.zero? and !resource.is_resigned
        weekly_resources_count += 1
        
        forecasts_this_week[resource.id] = alloc
      end
      
      current_total_available_resources = 0         # current_total_res_available
      current_total_allocated_resources = 0         # current_res_allocated
      
      skill_set.each do |skill|
        resource_count[skill] ||= 0
        resource_count[skill] += resource_countby(skill, week, accounting).to_i
        current_total_available_resources += resource_count[skill]
        skill_allocations[skill] ||= 0
        skill_allocations[skill] += get_total_allocations_per_skill(skill, week, accounting)
        resource_count_per_day = skill_allocations[skill].to_f/week.count.to_f
        current_total_allocated_resources += resource_count_per_day

        summary_this_week["resource_count"][to_yml(skill)] = resource_count[skill]
        summary_this_week["resource_count_per_day"][to_yml(skill)] = resource_count_per_day
        resource_count[skill] = 0
        skill_allocations[skill] = 0.0
      end

      percent_allocated = (current_total_available_resources.to_f / total_available_resources.to_f) * 100
      percent_unallocated = ((total_available_resources.to_f - current_total_available_resources.to_f ) / total_available_resources.to_f) * 100
      total_allocated_percent = (current_total_allocated_resources / weekly_resources_count.to_f) * 100
      
      # TODO: apply holidays
      summary_this_week["total_days"] = week.count
      summary_this_week["percent_allocated"] = percent_allocated
      summary_this_week["percent_unallocated"] = percent_unallocated
      summary_this_week["total_allocated_percent"] = total_allocated_percent
      summary_this_week["weekly_resources_count"] = weekly_resources_count
      summary_this_week["current_total_available_resources"] = current_total_available_resources
      summary_this_week["current_total_allocated_resources"] = current_total_allocated_resources
      
      forecasts[to_yml(week.last)] = forecasts_this_week
      summary[to_yml(week.last)] = summary_this_week
    end
    
    mgt[accounting] = {"forecasts" => forecasts, "updated_at" => updated_at, "summary" => summary}

    File.open("#{RAILS_ROOT}/config/rm_forecasts.yml", "w") do |out|
      YAML.dump(mgt, out)
    end
  end
end

#def resource_forecast_summary(resources, projects, skill_set, accounting, total_res_available)
#    str = ""
#    start_date, end_date = Date.today - 1.month, Date.today + 6.months
#    weeks = get_weeks_range(start_date, end_date)
#    total_days = 0
#    resource_count = {}
#    res_count_per_work_days = 0.0
#    res_allocations_skill = {}
#    str += "<div id='floating_tables_holder' style='width: #{weeks.count * 85}px'>"
#      weeks.each do |week|
#        total_days = week.count
#        weekly_resources_count = 0
#        str += "<div class='floating_table'>
#          <table id='allocation_week' class='list fixed'>
#            <tr>
#                <th>#{display_week(week)}</th>
#            </tr>"
#            resources.each do |resource|
#                res_allocations = resource.allocations(week, projects)
#                res_allocations_skill[resource.skill] = 0 if res_allocations_skill[resource.skill].nil?
#                resource_count[resource.skill] = 0 if resource_count[resource.skill].nil?
#                str += "<tr class='#{cycle('even', 'odd', :name => 'week_days')} #{allocation_to_class(res_allocations)}'>"
#                str += "<td>#{res_allocations}</td>"
#                res_allocations_skill[resource.skill] += res_allocations if !resource.is_resigned
#                resource_count[resource.skill] += 1 if !res_allocations.zero? and !resource.is_resigned
#              str += "</tr>"
#              weekly_resources_count += 1
#            end
#            reset_cycle('week_days')
#            current_total_res_available = 0
#            str += "<tr><th>&nbsp;</th></tr>"
#            skill_set.each do |skill|
#              str += "<tr style='background-color: #eee;'>"
#              resource_count[skill] = 0 if resource_count[skill].nil?
#              resource_count[skill] += resource_countby(skill, week, accounting)
#              str += "<td>#{resource_count[skill]}</td>"
#              current_total_res_available += resource_count[skill] ? resource_count[skill] : 0.0
#              resource_count[skill] = 0
#              str += "</tr>"
#            end
#            str += "<tr style='background-color: #eee;'><td>&nbsp;</td></tr>
#            <tr style='background-color: #eee;'>
#              <td>#{current_total_res_available}</td>
#            </tr>"
#            percent_allocated = (get_float(current_total_res_available) / get_float(total_res_available)) * 100
#            percent_unallocated = (get_float(total_res_available - current_total_res_available) / get_float(total_res_available)) * 100
#            str += "<tr style='background-color: #eee;'><td>#{get_string(percent_unallocated.round(2))}%</td></tr>
#            <tr style='background-color: #eee;'><td>#{get_string(percent_allocated.round(2))}%</td></tr>
#            <tr><th>#{total_days}</th></tr>"
#            current_res_allocated = 0.0
#            skill_set.each do |skill|
#              str += "<tr style='background-color: #eee;'>"
#                res_allocations_skill[skill] = 0 if res_allocations_skill[skill].nil?
#                res_allocations_skill[skill] += get_total_allocations_per_skill(skill, week, accounting)
#                res_count_per_work_days = res_allocations_skill[skill] ? (get_float(res_allocations_skill[skill])/get_float(total_days)) : 0.0
#                str += "<td>#{get_string(res_count_per_work_days)}</td>"
#                current_res_allocated += res_count_per_work_days
#                res_allocations_skill[skill] = 0.0
#              str += "</tr>"
#            end
#            str += "<tr style='background-color: #eee;'><td>&nbsp;</td></tr>
#            <tr style='background-color: #eee;'><td>#{get_string(current_res_allocated.round(2))}</td></tr>
#            <tr style='background-color: #eee;'><td>#{get_string(weekly_resources_count)}</td></tr>"
#            total_allocated_percent = (current_res_allocated / get_float(weekly_resources_count)) * 100
#            str += "<tr style='background-color: #eee;'><td>#{get_string(total_allocated_percent.round(2))}%</td></tr>
#          </table>
#        </div>"
#      end
#      str += "</div>"
#  end
