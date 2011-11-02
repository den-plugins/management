require_dependency 'project'

module Management
  module ProjectPatch
    def self.included(base)
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      base.class_eval do
        unloadable
        attr_accessor :project_type, :accounting_type, :category
        
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
      
      #TODO: Call this method every initialization of an instance of Project
      def custom_field_values
        self.project_type = field_project_type
        self.accounting_type = field_accounting_type
        self.category = field_category
      end
      
      def field_project_type
        type = custom_values.find(:first, :select => "custom_values.value",
                                                         :include => [:custom_field], :conditions => ["custom_fields.name = 'Project Type'"])
        type.nil? ? nil : type.value
      end
      
      def field_category
        type = custom_values.find(:first, :select => "custom_values.value",
                                                         :include => [:custom_field], :conditions => ["custom_fields.name = 'Category'"])
        type.nil? ? nil : type.value
      end
   
      def field_accounting_type
        return nil if acctg_type.nil?
        Enumeration.accounting_types.find(:first, :select => "name", :conditions => ["id = ?", acctg_type]).name
      end
    end
  end
end
