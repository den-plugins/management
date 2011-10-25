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
      end
    end
    
    module ClassMethods
    end
    
    module InstanceMethods
    
      def skill
        s = custom_values.find(:first, :include => [:custom_field], :conditions => "custom_fields.name = 'Skill or Role'")
        s.nil? ? nil : s.value
      end

      def is_resigned
        r = custom_values.find(:first, :include => [:custom_field], :conditions => "custom_fields.name = 'Resigned Date'")
        date = r.nil? ? nil : r.value
        return (date.nil? or date.blank?)? false : true
      end
    end
  end
end
