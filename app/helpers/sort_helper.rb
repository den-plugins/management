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

    def to_full_sql_with_custom(options={})
      customized_model_name = nil
      custom_field = nil
      customized_table = nil
      custom_field_model = nil
      custom_fields = {}
      order_clauses = []
      default_order = options.delete(:order)

      @criteria.each do |key, asc|
        if s = @available_criteria[key]
          if key.to_s =~ /^\w+\-\w+\-\w+$/
            if custom_fields.empty?
              customized_model_name = key.to_s.split('-')[1]
              custom_field = key.to_s.split('-')[2]
              customized_table = customized_model_name.classify.constantize.table_name
              custom_field_model = "#{customized_model_name}_custom_field".classify.constantize
              custom_fields = Hash[*custom_field_model.all.collect{ |field| [field.name.strip.downcase.gsub(/ /, '_'), field.name] }.flatten]
            end

            if custom_fields.keys.include?(custom_field)
              options.merge!(:joins => %{LEFT OUTER JOIN (SELECT customized_id, value FROM custom_values 
                  LEFT OUTER JOIN custom_fields ON custom_fields.id = custom_values.custom_field_id
                  WHERE custom_values.customized_type = '#{customized_model_name.classify}' AND custom_fields.name = '#{custom_fields[custom_field]}'
                  ) #{custom_field} ON #{custom_field}.customized_id = #{customized_table}.id
                })

              order_clauses << (asc ? "#{custom_field}.value" : "#{custom_field}.value DESC")
            end
          else
            order_clauses.concat(asc ? s.to_a : s.to_a.collect {|c| "#{c} DESC"})
          end
        end
      end

      options.merge(:order => order_clauses.push(default_order).compact.join(', '))
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

  def full_sort_clause(options={})
    @sort_criteria.to_full_sql_with_custom(options)
  end
  
  def sort_header_tag_without_update(column, options = {})
    caption = options.delete(:caption) || column.to_s.humanize
    default_order = options.delete(:default_order) || 'asc'
    options[:title] = l(:label_sort_by, "\"#{caption}\"") unless options[:title]
    content_tag('th', sort_link_without_update(column, caption, default_order), options)
  end
  
  def sort_link_without_update(column, caption, default_order)
    css, order = nil, default_order
    if column.to_s == @sort_criteria.first_key
      if @sort_criteria.first_asc?
        css = 'sort asc'
        order = 'desc'
      else
        css = 'sort desc'
        order = 'asc'
      end
    end
    caption = column.to_s.humanize unless caption
    
    sort_options = { :sort => @sort_criteria.add(column.to_s, order).to_param }
    url_options = params.has_key?(:set_filter) ? sort_options : params.merge(sort_options)
    url_options = url_options.merge(:project_id => params[:project_id]) if params.has_key?(:project_id)
    link_to_remote(caption,
                  {:url => url_options, :method => :get},
                  {:href => url_for(url_options),
                   :class => css})
  end

  def sort_link(column, caption, default_order)
    css, order = nil, default_order

    if column.to_s == @sort_criteria.first_key
      if @sort_criteria.first_asc?
        css = 'sort asc'
        order = 'desc'
      else
        css = 'sort desc'
        order = 'asc'
      end
    end
    caption = column.to_s.humanize unless caption

    sort_options = { :sort => @sort_criteria.add(column.to_s, order).to_param }
    # don't reuse params if filters are present
    url_options = params.has_key?(:set_filter) ? sort_options : params.merge(sort_options)

     # Add project_id to url_options
    url_options = url_options.merge(:project_id => params[:project_id]) if params.has_key?(:project_id)
    url_options = url_options.merge(:caption => caption.to_param)
    link_to_remote(caption,
                  {:update => "content", :url => url_options, :method => :get},
                  {:href => url_for(url_options),
                   :class => css})
  end
end
