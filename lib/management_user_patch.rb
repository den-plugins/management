require_dependency 'user'
include ResourceManagementsHelper

module Management
  module UserPatch
    def self.included(base)
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      base.class_eval do
        unloadable
        
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

        c = ARCondition.new("status = 1")
        c << "LOWER(users.lastname) LIKE '#{filters[:lastname].strip.downcase}'" unless filters[:lastname].blank?
        c << "users.is_engineering is true" if !filters[:is_engineering].blank? and filters[:is_engineering].to_i.eql?(1)
        c << "users.skill = '#{filters[:skill_or_role]}'" unless filters[:skill_or_role].blank?
        c << "users.location = '#{filters[:location]}'" unless filters[:location].blank?
        c << "users.id in (select users.id from users #{custom_values_join} #{custom_fields_join} \
                    where custom_fields.name='Organization' and custom_values.value='#{filters[:organization]}')" unless filters[:organization].blank?
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
        return (date.nil? or date.blank?) ? false : true
      end
      
      def hired_date
        c = custom_values.detect {|v| v.mgt_custom "Employment Start"}
        c ? c.value : nil
      end
      
      def organization
        c = custom_values.detect {|v| v.mgt_custom "Organization"}
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

      def total_expected(from, to)
        weeks = get_weeks_range(from, to)
        texpected = 0
        weeks.each do |week|
          texpected += (week.count * 8) # 40 hours is the expected hours per week, 8 hours per day and 5 days a week
        end
        texpected
      end
      
      def detect_holidays_in_week(location, day)
        locations = [6]
        locations << location if location
        locations << 3 if location.eql?(1) || location.eql?(2)
        Holiday.count(:all, :conditions => ["event_date=? and location in (#{locations.join(', ')})", day])
      end
    end
  end
end
