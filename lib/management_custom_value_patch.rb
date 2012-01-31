require_dependency 'custom_value'

module Management
  module CustomValuePatch
    def self.included(base)
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      base.class_eval do
        unloadable
        validate :date_entries_must_be_in_calendar
      end
    end
    
    module ClassMethods
    end
    
    module InstanceMethods
      def date_entries_must_be_in_calendar
        if custom_field.field_format.eql?('date')
          begin
            date = value.to_date
            errors.add(:value, :not_a_date) if Date.valid_date?(date.year, date.month, date.day).nil?
          rescue ArgumentError
            errors.add(:value, :not_a_date)
          end
        end
      end
      
      def mgt_custom(field)
        custom_field.name.downcase.eql? field.downcase
      end
    end
  end
end
