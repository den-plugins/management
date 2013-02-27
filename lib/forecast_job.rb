class ForecastJob < Struct.new(:from, :to, :accounting, :resources_no_limit, :skill_set, :projects, :total_available_resources)
  include Delayed::ScheduledJob
  include ResourceManagementsHelper

  run_every(Time.parse("12am") + 1.day)
  
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
    
    weeks = get_weeks_range(from.to_date, to.to_date)
    weeks.each do |week|
      weekly_resources_count = 0
      forecasts_this_week = forecasts[to_yml(week.last)] || {}
      summary_this_week = summary[to_yml(week.last)] || {}
      summary_this_week["resource_count"] = {}
      summary_this_week["resource_count_per_day"] = {}

      @resources_no_limit.each do |resource|
#        resource = User.find(r)

        resignation_date = to_date_safe(resource.resignation_date)
        hired_date = to_date_safe(resource.hired_date)
        start_date = hired_date && hired_date > week.first && hired_date < week.last ? hired_date : week.first
        end_date = resignation_date && resignation_date > week.first && resignation_date < week.last ? resignation_date : week.last
        total_working_days = (start_date..end_date).count
        working_days = 0
        alloc = resource.allocations(week, @projects)

        project_allocations = resource.members.collect(&:resource_allocations).flatten.select do |v|
          @projects.include? v.member.project_id
        end
        if allocations = project_allocations.select {|a| a.start_date <= week.last && a.end_date >= week.first}.uniq
          allocations.each do |allocation|
            working_days = total_working_days - detect_holidays_in_week(allocation.location, week)
          end
        end
        skill = resource.skill
        skill_allocations[skill] ||= 0
        skill_allocations[skill] += alloc unless resource.is_resigned
        resource_count[skill] ||= 0
        resource_count[skill] += 1 if alloc.zero? && !resource.is_resigned || alloc < working_days && !resource.is_resigned

        if resignation_date && resignation_date > week.first && hired_date && hired_date < week.last
          weekly_resources_count += 1
        elsif !resignation_date && hired_date && hired_date < week.last
          weekly_resources_count += 1
        end
        
        forecasts_this_week[resource.id] = working_days.eql?(0) ? 0 : alloc/working_days
      end
      
      current_total_available_resources = 0         # current_total_res_available
      current_total_allocated_resources = 0         # current_res_allocated
      
      skill_set.each do |skill|
#        resource_count[skill] ||= 0
#        resource_count[skill] += resource_countby(skill, week, accounting).to_i
        current_total_available_resources += resource_count[skill].to_i
#        skill_allocations[skill] ||= 0
#        skill_allocations[skill] += get_total_allocations_per_skill(skill, week, accounting)
        resource_count_per_day = skill_allocations[skill].to_f/week.count.to_f
        current_total_allocated_resources += resource_count_per_day

        summary_this_week["resource_count"][to_yml(skill)] = resource_count[skill].to_i
        summary_this_week["resource_count_per_day"][to_yml(skill)] = resource_count_per_day
        resource_count[skill] = 0
        skill_allocations[skill] = 0.0
      end

      percent_unallocated = (current_total_available_resources.to_f / weekly_resources_count.to_f) * 100
      percent_allocated = 100 - percent_unallocated
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

  def detect_holidays_in_week(location, week)
    locations = [6]
    locations << location if location
    locations << 3 if location.eql?(1) || location.eql?(2)
    Holiday.count(:all, :conditions => ["event_date > ? and event_date < ? and location in (#{locations.join(', ')})", week.first, week.last])
  end
end
