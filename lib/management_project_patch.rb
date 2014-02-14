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

      def list_for_billing(from, to)
        #active, development, Billable, !closed
        active.find(:all, :include => [:accounting, :custom_values]).select { |p|
          p.is_dev_project? &&
          p.accounting_type == 'Billable' &&
         (p.closure_date.nil? || p.closure_date >= from)
        }.sort_by { |p| p.name.downcase }
      end

      def list_on_going_development_and_admin(from, to)
        #active, development & admin types, !closed
        active.find(:all, :include => [:custom_values], :order => 'projects.name ASC').select { |p|
          (p.is_admin_project? || p.is_dev_project?) &&
          (p.closure_date.nil? || p.closure_date >= from)
        }.sort_by { |p| p.name.downcase }
      end
    end

    module InstanceMethods

      def is_admin_project?
        custom_values.detect{|x| x.custom_field_id == 15 && x.value.eql?("Admin")} ? true : false
      end

      def is_dev_project?
        custom_values.detect{|x| x.custom_field_id == 15 && x.value.eql?("Development")} ? true : false
      end

      def get_member
        @project.members.detect{|u| u.user_id == User.current.id}
      end

      def get_user_members(user_id)
        @project.members.detect{|u| u.user_id == user_id}
      end

      def archived?
        status.eql? 9 ? true : false
      end

      def user_allocated_end_date
        if is_admin_project?
          parent.children.each do |child|
            @project = child if child.custom_values.detect{|b| b.value ==  "Development"}
          end
          if get_member && get_member.resource_allocations
            latest_allocation = @project.members.detect{|u| u.user_id == User.current.id}.resource_allocations.last.end_date if @project.members && User.current
          end
        end
        Date.today <= latest_allocation && lock_time_logging ? true : false
      end

      def user_allocated_on_proj(user_id, log_date=Date.today)
        allow_log = false
        current_user = User.find(user_id)
        exempted_projects = ["exist engineering admin","engineering project shadow","exist pre-sales"]
        unless exempted_projects.include?(name.downcase)
          if is_admin_project?
            parent.children.each do |child|
              @project = child if child.custom_values.detect{|b| b.value ==  "Development"}
              member = get_user_members(user_id) if @project
              if @project && member
                member.resource_allocations.each do |allocation|
                  if allocation
                    start_date = allocation.start_date
                    end_date = allocation.end_date
                    allow_log = true if log_date.between?(start_date,end_date)
                  end
                end
              end

            end
          elsif is_dev_project?
            @project = self
            member = get_user_members(user_id)
            if member
              member.resource_allocations.each do |allocation|
                if allocation
                  start_date = allocation.start_date
                  end_date = allocation.end_date
                  allow_log = true if log_date.between?(start_date,end_date)
                end
              end
            end

          end
        else
          allow_log = true
        end
        allow_log
      end

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
        (category && development?) ? category.downcase.include?("interactive") : false
      end

      def dev_pre_sales?
        (category && development?) ? category.downcase.include?("pre-sales") : false
      end

      def fixed_cost?
        billing_model.scan(/^(Fixed)/i).flatten.present? if billing_model
      end

      def t_and_m?
        billing_model.scan(/^(T and M)/i).flatten.present? if billing_model
      end

      def in_warranty?
        if (from=actual_end_date) && (to=maintenance_end)
          from, to = to, from if from && to && from > to
          (from .. to).include?(Date.today)
        end
      end

      def in_programme?
        development? and !dev_interactive? and !dev_pre_sales? and !in_warranty?
      end

      def closed?
        temp = custom_values.detect{|x| x.custom_field.name.downcase["closure"]}
        (temp and !temp.value.blank? and temp.value.to_date < Date.current) ? true : false
      end

      def closure_date
        date = custom_values.detect { |x| x.custom_field.name.downcase["closure"] }
        (date && date.value.present?) ? date.value.to_date : nil
      end
    end
  end
end
