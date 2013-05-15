map.connect 'resource_managements/project_billing_detail', :controller => 'resource_managements', :action => 'project_billing_detail'
map.connect 'resource_managements/forecast_billable_detail', :controller => 'resource_managements', :action => 'forecasts_billable_detail'
map.connect 'resource_managements/forecast_billable_detail/export', :controller => 'resource_managements', :action => 'export', :method => :get
map.connect 'resource_managements/default_rate', :controller => 'resource_managements', :action => 'default_rate', :method => :get
map.connect 'resource_managements/save_default_rate', :controller => 'resource_managements', :action => 'save_default_rate', :method => :put
map.connect 'resource_managements/forecast_billable_detail/export_project_billing_detail', :controller => 'resource_managements', :action => 'export_project_billing_detail', :method => :get

