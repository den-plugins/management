require 'redmine'
require 's3_attachment/s3_send_file'
require 'dispatcher'

require 'pm_member_patch'
require 'pm_project_patch'
require 'management_custom_value_patch'
require 'management_project_patch'
require 'management_user_patch'

Dispatcher.to_prepare do
  CustomValue.send(:include,  Management::CustomValuePatch)
  Project.send(:include, Management::ProjectPatch)
  User.send(:include, Management::UserPatch)
end

Redmine::Plugin.register :management do
  name 'Redmine Management Plugin'
  author 'Exist Den Team'
  description 'This is a plugin for Redmine that serves as a dashboard for Management Tools'
  version '0.0.1'

  project_module :management do
    permission :manage_resources, {:resource_managements => [:index, :get, :allocations]}, :public => false
  end

  menu :top_menu,
              :resource_management,
            {:controller => "resource_managements", :action => "index" },
              :caption => "Management",
              :before => :administration,
              :if => Proc.new { User.current.allowed_to?(:manage_resources, nil, :global => true) || User.current.admin? }

  Redmine::MenuManager.map :resource_management do |menu|
    menu.push :dashboard, {:controller => 'resource_managements', :action => 'index' }
    menu.push :allocations, {:controller => 'resource_managements', :action =>'allocations' }, :caption => 'Resource Allocation'
    menu.push :forecasts, {:controller => 'resource_managements', :action =>'forecasts' }, :caption => 'Resource Forecast Summary'
    menu.push :users, {:controller => 'resource_managements', :action => 'users'}, :caption => 'User Management'
  end

end
