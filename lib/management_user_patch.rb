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
    end
    
    module InstanceMethods

      def set_non_engr_on
        if !self.is_engineering
          self.non_engr_on = Date.today
        else
          self.non_engr_on = nil
        end
      end
    
      def skill
        s = custom_values.find(:first, :include => [:custom_field], :conditions => "custom_fields.name = 'Skill or Role' or custom_fields.id = 19")
        s.nil? ? nil : s.value
      end

      def is_resigned
        r = custom_values.find(:first, :include => [:custom_field], :conditions => "custom_fields.name = 'Employment End'")
        date = r.nil? ? nil : r.value
        return (date.nil? or date.blank?)? false : true
      end
      
      def location
        s = custom_values.find(:first, :include => [:custom_field], :conditions => "custom_fields.name = 'Location' or custom_fields.id = 16")
        s.nil? ? nil : s.value
      end
      
      def allocations(week, rate=nil, acctg=nil)
        days, cost = 0, 0
        project_allocations = ResourceAllocation.find(:all, :include => [:member], :conditions => ["members.user_id = ?", id]).select do |alloc|
          project = alloc.member.project
          if acctg && acctg.eql?('Both')
            project.project_type.eql?('Development') && (project.accounting_type.eql?('Billable') || project.accounting_type.eql?('Non-billable'))
          else
            project.project_type.eql?('Development') &&  project.accounting_type.eql?(acctg || 'Billable')
          end
        end
        week.each do |day|
          allocations = project_allocations.select{ |a| a.start_date <= day && a.end_date >= day}.uniq
          if allocations.any?
            allocations.each do |allocation|
              days += (1 * (allocation.resource_allocation.to_f/100).to_f) unless allocation.resource_allocation.eql? 0
            end
          end
        end
        cost = days * (rate.to_f)
        rate ? [days, cost] : days
      end
    end
  end
end
