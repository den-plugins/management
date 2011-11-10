require_dependency 'custom_value'

module Management
  module CustomValuePatch
    def self.included(base)
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      base.class_eval do
        unloadable
      end
    end
    
    module ClassMethods
    end
    
    module InstanceMethods
      def mgt_custom(field)
        custom_field.name.downcase.eql? field.downcase
      end
    end
  end
end
