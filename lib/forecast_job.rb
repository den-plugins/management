class ForecastJob < Struct.new(:accounting, :resources_no_limit, :skill_set, :projects, :total_available_resources)
  include ResourceManagementsHelper
  
  def perform
    if FileTest.exists?("#{RAILS_ROOT}/config/rm_forecasts.yml")
      mgt = (file=YAML.load(File.open("#{RAILS_ROOT}/config/rm_forecasts.yml"))) ? file : {}
    else
      mgt = {}
    end

    @resources_no_limit = User.find(:all, :conditions => ["id IN (#{resources_no_limit.join(',')})"])
    @projects = projects
    
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

      @resources_no_limit.each do |resource|
#        resource = User.find(r)
        alloc = resource.allocations(week, @projects)
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
#        resource_count[skill] ||= 0
#        resource_count[skill] += resource_countby(skill, week, accounting).to_i
        current_total_available_resources += resource_count[skill]
#        skill_allocations[skill] ||= 0
#        skill_allocations[skill] += get_total_allocations_per_skill(skill, week, accounting)
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
