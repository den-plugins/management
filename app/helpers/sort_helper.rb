require_dependency 'sort_helper'

module SortHelper
  class SortCriteria
    def to_sql_with_custom
      custom_select= []
      custom_fields = UserCustomField.all.collect {|u| u.name.strip.downcase.gsub(/ /, '_') }
      sql = @criteria.collect do |k,o|
        if s = @available_criteria[k]
          if custom_fields.include?(k)
            if o
              cselect = "(select value from users inner join custom_values on \
                                                customized_id=users.id and customized_type='User' \
                                                where custom_fields.name='#{eq_custom(s)}' order by value limit 1)"
              custom_select += [cselect]
              "#{cselect}, custom_values.value"
            else
              s.to_a.collect {|c|
                custom_select = "(select value from users inner join custom_values on \
                                                  customized_id=users.id and customized_type='User' \
                                                  where custom_fields.name='#{eq_custom(s)}' order by value desc limit 1)"
                custom_select += [cselect]
                "#{cselect}, custom_values.value"
              }.join(', ')
            end
          else
            (o ? s.to_a : s.to_a.collect {|c| "#{c} DESC"}).join(', ')
          end
        end
      end.compact.join(', ')
      #sql.blank? ? nil : sql
      [(sql.blank? ? nil : sql), (custom_select.blank? ? nil : custom_select.compact.join(', '))]
    end
    
    def eq_custom(custom_field)
      case custom_field
        when "location"; 'Location'
        when "skill_or_role"; 'Skill or Role'
        when "hired_date"; 'Hired Date'
        when "organization"; 'Organization'
      end
    end
  end
  
  def mgt_sort_clause
    @sort_criteria.to_sql_with_custom.collect
  end
end
