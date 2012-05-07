require_dependency 'user'
include ResourceManagementsHelper

module Management
  module UserPatch
    def self.included(base)
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      base.class_eval do
        unloadable

        const_set("SKILLS", ["Java", "RoR", "Architect", "PM/BA", "Interactive", "QA", "Sys Ad",
                  "Mobile", "Tech Support", "Tech Writer", "Others", "N/A"])
        const_set("LOCATIONS", ["Manila", "Cebu", "US", "N/A"])

        has_many :assumptions, :foreign_key => :owner
        has_many :risks, :foreign_key => :owner
        has_many :pm_dashboard_issues, :foreign_key => :owner

        named_scope :engineers, :conditions => ["is_engineering = true"], :order => 'firstname'

        before_save :set_non_engr_on
        cattr_accessor :tmp_resources, :tmp_resources_no_limit, :tmp_skillset
      end
    end

    module ClassMethods
      def resource_skills
        res_skills = find(:all, :select => "distinct(skill)", :conditions => "skill is not NULL")
        res_skills.empty? ? [] : res_skills.map {|u| u.skill}
      end

      def generate_user_mgt_condition(filters)
        custom_values_join = "left outer join custom_values on users.id=custom_values.customized_id and custom_values.customized_type='User' "
        custom_fields_join = "left outer join custom_fields on custom_fields.id=custom_values.custom_field_id"

        c = ARCondition.new("users.status = 1")
        unless filters.empty?
          c << "LOWER(users.lastname) LIKE '#{filters[:lastname].strip.downcase}'" if filters[:lastname] and !filters[:lastname].blank?
          c << "users.is_engineering is true" if filters[:is_engineering] and !filters[:is_engineering].blank? and filters[:is_engineering].to_i.eql?(1)
          c << "users.skill = '#{filters[:skill_or_role]}'" if filters[:skill_or_role] and !filters[:skill_or_role].blank?
          c << "users.location = '#{filters[:location]}'" if filters[:location] and !filters[:location].blank?
          c << "users.id in (select users.id from users #{custom_values_join} #{custom_fields_join} \
                      where custom_fields.name='Organization' and custom_values.value='#{filters[:organization]}')" if filters[:organization] and !filters[:organization].blank?
          c << "users.id in (select users.id from users #{custom_values_join} #{custom_fields_join} \
                      where custom_fields.name='Employee Status' and custom_values.value<>'Resigned')" if filters[:is_employed] and !filters[:is_employed].blank? and filters[:is_employed].to_i.eql?(1)
        end
        c
      end
    end

    module InstanceMethods

      def set_non_engr_on
        if !self.is_engineering
          self.non_engr_on = Date.today
        else
          self.non_engr_on = nil
        end
      end

      # Return user's full name for display
      def display_name
        name :lastname_coma_firstname
      end

      def is_resigned
        r = custom_values.detect {|v| v.mgt_custom "Employment End"}
        date = r.nil? ? nil : r.value
        return (date.nil? or date.blank? or date.to_date > Date.today) ? false : true
      end

      def employee_status
        e = custom_values.detect {|v| v.mgt_custom "Employee Status"}
        status = e ? e.value : nil
      end

      def resignation_date
        r = custom_values.detect {|v| v.mgt_custom "Employment End"}
        r ? r.value : nil
      end

      def hired_date
        c = custom_values.detect {|v| v.mgt_custom "Employment Start"}
        c ? c.value : nil
      end

      def organization
        c = custom_values.detect {|v| v.mgt_custom "Organization"}
        c ? c.value : nil
      end

      def get_resignation_date
        r = User.find(id).custom_values.detect {|v| v.mgt_custom "Employment End"}
        r ? r.value : nil
      end

      def get_hired_date
        c = User.find(id).custom_values.detect {|v| v.mgt_custom "Employment Start"}
        c ? c.value : nil
      end

      def get_organization
        c = User.find(id).custom_values.detect {|v| v.mgt_custom "Organization"}
        c ? c.value : nil
      end

      def allocations(week, filtered_projects, rate=nil)
        days, cost = 0, 0
        project_allocations = members.collect(&:resource_allocations).flatten.select do |alloc|
          filtered_projects.include? alloc.member.project_id
        end

        week.each do |day|
          unless day.wday.eql?(0) || day.wday.eql?(6)
            if allocations = project_allocations.select {|a| a.start_date <= day && a.end_date >= day}.uniq
              allocations.each do |alloc|
                holiday = alloc.nil? ? 0 : detect_holidays_in_week(alloc.location, day)
                days += (1 * (alloc.resource_allocation.to_f/100).to_f) if holiday.eql?(0)
              end unless allocations.empty?
            end
          end
        end unless project_allocations.empty?
        cost = days * (rate.to_f)
        rate ? [days, cost] : days
      end

      # modified allocations method to consider 100% of total allocations.
      def allocations_modified(week, filtered_projects, rate=nil)
        days, cost = 0, 0
        project_allocations = members.collect(&:resource_allocations).flatten.select do |alloc|
          filtered_projects.include? alloc.member.project_id
        end

        week.each do |day|
          unless day.wday.eql?(0) || day.wday.eql?(6)
            if allocations = project_allocations.select {|a| a.start_date <= day && a.end_date >= day}.uniq
              ra = 0
              allocations.each do |alloc|
                holiday = alloc.nil? ? 0 : detect_holidays_in_week(alloc.location, day)
                if holiday.eql?(0)
                  ra += alloc.resource_allocation
                end
              end unless allocations.empty?
              div = (ra > 100 ? round_up(ra) : 100)
              days += (1 * (ra.to_f / div).to_f)
            end
          end
        end unless project_allocations.empty?
        cost = days * (rate.to_f)
        rate ? [days, cost] : days
      end

      def total_expected(from, to, project_ids)
        h_date, r_date = to_date_safe(hired_date), to_date_safe(resignation_date)
        f = (((from..to).include_with_range?(h_date))? h_date : from)
        t = (((from..to).include_with_range?(r_date))? r_date : to)
        weeks = get_weeks_range(f, t)
        texpected = 0
        weeks.each do |week|
          texpected += allocations_modified(week, project_ids) * 8 # 40 hours is the expected hours per week, 8 hours per day
        end
        texpected
      end

      # for counting available hours in forecast billable data
      def available_hours(from, to, project_ids)
        h_date, r_date = to_date_safe(hired_date), to_date_safe(resignation_date)
        f = ((from..to).include_with_range?(h_date) ? h_date : from)
        t = ((from..to).include_with_range?(h_date) ? r_date : to)
        total = 0

        allocations = ResourceAllocation.all(:conditions => ['member_id IN (?) AND ((start_date BETWEEN ? AND ?) OR (end_date BETWEEN ? AND ?))',
          members.find_by_project_id(project_ids).to_a.map(&:id), f, t, f, t])

        allocations.each do |allocation|
          s = [f, allocation.start_date].max
          e = [t, allocation.end_date].min
          total += ((e - s).to_i - holidays_between?(s, e, allocation.location)) * 8
        end

        return total
      end

      def detect_holidays_in_week(location, day)
        locations = [6]
        locations << location if location
        locations << 3 if location.eql?(1) || location.eql?(2)
        Holiday.count(:all, :conditions => ["event_date=? and location in (#{locations.join(', ')})", day])
      end

      def holidays_between?(from, to, location)
        locations = [6]
        locations << location if location
        locations << 3 if location.eql?(1) || location.eql?(2)
        Holiday.count(:conditions => ["(event_date BETWEEN ? AND ?) AND location IN (?)", from, to, locations])
      end
    end
  end
end