require_dependency 'custom_value'

module Management
  module CustomValuePatch
    def self.included(base)
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      base.class_eval do
        unloadable
        validate :date_entries_must_be_in_calendar, :if => :is_date_format?
      end
    end
    
    module ClassMethods
    end
    
    module InstanceMethods
      def is_date_format?
        custom_field && custom_field.field_format.eql?('date')
      end
      
      def date_entries_must_be_in_calendar
        date = Date.parse(value)  unless value.blank?
        rescue  ArgumentError
          errors.add(:value, :not_a_date)
      end
      
      def mgt_custom(field)
        custom_field.name.downcase.eql? field.downcase
      end
    end
  end
end
