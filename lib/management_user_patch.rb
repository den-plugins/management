require_dependency 'user'

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
      end
    end
    
    module ClassMethods
      def resource_skills
        res_skills = CustomField.find(:first, :conditions => "type = 'UserCustomField' and name = 'Skill or Role'")
        return (res_skills.nil? ? [] : res_skills.possible_values)
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
    
      def location
        c = custom_values.detect {|v| v.mgt_custom "Location"}
        c ? c.value : nil
      end
      
      def skill
        c = custom_values.detect {|v| v.mgt_custom "Skill or Role"}
        c ? c.value : nil
      end
      
      def is_resigned
        r = custom_values.detect {|v| v.mgt_custom "Employment End"}
        date = r.nil? ? nil : r.value
        return (date.nil? or date.blank?) ? false : true
      end
      
      def allocations(week, filtered_projects, rate=nil)
        days, cost = 0, 0
        project_allocations = ResourceAllocation.find(:all, :include => [:member], :conditions => ["members.user_id = ?", id]).select do |alloc|
          project = alloc.member.project
          filtered_projects.include? project.id
        end
        
        unless project_allocations.empty?
          week.each do |day|
            allocations = project_allocations.select{ |a| a.start_date <= day && a.end_date >= day}.uniq
            if allocations.any?
              allocations.each do |allocation|
                days += (1 * (allocation.resource_allocation.to_f/100).to_f) unless allocation.resource_allocation.eql? 0
              end
            end
          end
        end
        cost = days * (rate.to_f)
        rate ? [days, cost] : days
      end
    end
  end
end
