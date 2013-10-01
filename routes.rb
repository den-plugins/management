map.connect 'resource_managements/project_billing_detail', :controller => 'resource_managements', :action => 'project_billing_detail'
map.connect 'resource_managements/resource_billing_detail', :controller => 'resource_managements', :action => 'resource_billing_detail'
map.connect 'resource_managements/forecast_billable_detail', :controller => 'resource_managements', :action => 'forecasts_billable_detail'
map.connect 'resource_managements/forecast_billable_detail/export', :controller => 'resource_managements', :action => 'export', :method => :get
map.connect 'resource_managements/default_rate', :controller => 'resource_managements', :action => 'default_rate', :method => :get
map.connect 'resource_managements/save_default_rate', :controller => 'resource_managements', :action => 'save_default_rate', :method => :put
map.connect 'resource_managements/project_billing_detail/export_project_billing_detail', :controller => 'resource_managements', :action => 'export_project_billing_detail', :method => :get
map.connect 'resource_managements/project_billing_detail/export_weekly_actual_hours', :controller => 'resource_managements', :action => 'export_weekly_actual_hours', :method => :get
map.connect 'resource_managements/resource_billing_detail/export_resource_billing_detail', :controller => 'resource_managements', :action => 'export_resource_billing_detail', :method => :get
