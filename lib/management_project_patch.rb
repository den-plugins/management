require_dependency 'project'

module Management
  module ProjectPatch
    def self.included(base)
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      base.class_eval do
        unloadable
        cattr_accessor :tmp_projects
        named_scope :development, :select => "id",
                                  :joins => "LEFT OUTER JOIN custom_fields ON custom_fields.id=custom_values.custom_field_id",
                                  :include => [:custom_values],
                                  :conditions => "custom_values.customized_type='Project' and custom_fields.name='Project Type' and custom_values.value='Development'",
                                  :order => 'projects.name ASC'
      end
    end
    
    module ClassMethods
      def project_categories
        proj_categories = CustomField.find(:first, :conditions => "type = 'ProjectCustomField' and name = 'Category'")
        return (proj_categories.nil? ? [] : proj_categories.possible_values)
      end
    end
    
    module InstanceMethods
      
      def project_type
        c = custom_values.detect {|v| v.mgt_custom "Project Type"}
        c ? c.value : nil
      end
      
      def category
        c = custom_values.detect {|v| v.mgt_custom "Category"}
        c ? c.value : nil
      end
   
      def accounting_type
        accounting ? accounting.name : nil
      end
      
      def for_time_logging_only?
        c = custom_values.detect {|v| v.mgt_custom "For time logging only"}
        c ? c.value.eql?("1") : false
      end
      
      def development?
        project_type ? project_type.eql?("Development") : false
      end
      
      def dev_interactive?
        (category && development?) ? category.eql?("Interactive") : false
      end

      def pre_sales?
        (category && development?) ? category.eql?("Pre-Sales") : false
      end

      def fixed_cost?
        billing_model.scan(/^(Fixed)/i).flatten.present? if billing_model
      end
      
      def t_and_m?
        billing_model.scan(/^(T and M)/i).flatten.present? if billing_model
      end
    end
  end
end
