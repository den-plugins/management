require 'redmine'
require 's3_attachment/s3_send_file'

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
              :if => Proc.new { User.current.allowed_to?(:manage_resources, nil, :global => true) }

  Redmine::MenuManager.map :resource_management do |menu|
    menu.push :dashboard, {:controller => 'resource_managements', :action => 'index' }
    menu.push :allocations, {:controller => 'resource_managements', :action =>'allocations' }, :caption => 'Resource Allocation'
  end

end
