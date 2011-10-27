class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations
  menu_item :forecasts, :only => :forecasts

  before_filter :require_management
  helper :resource_costs
  
  def index
  end
  
  def allocations
    @projects = Project.active.find(:all, :order => 'name ASC').select {|project| project.project_type.eql?('Development')}
    @members = []
    @projects.each{|project| @members += project.members.select {|m| !m.user.is_resigned}}
  end
  
  def forecasts
    limit = per_page_option
    dev_projects = Project.all.collect {|p|
      if params[:acctg] && params[:acctg].eql?('Both')
        p.id if p.project_type.eql?('Development') && (p.accounting_type.eql?('Billable') || p.accounting_type.eql?('Non-billable'))
      else
        p.id if p.project_type.eql?('Development') && p.accounting_type.eql?(params[:acctg] || 'Billable')
      end
    }.compact.uniq.join(', ')
    
    if dev_projects.empty?
      @resources = []
    else
      development = "and projects.id IN (#{dev_projects})"
      active_project = "select id, status from projects where projects.id = members.project_id and projects.status = 1 #{development}"
      statement = "exists (select user_id, project_id from members where members.user_id = users.id and exists (#{active_project}))"
      @resources_no_limit = User.active.engineers.find(:all,
                                                                :include => [:projects, :custom_values, :members],
                                                                :conditions => statement,
                                                                :order => "firstname ASC, lastname ASC")
      @resource_count = @resources_no_limit.count
      @resource_pages = Paginator.new self, @resource_count, limit, params['page']
      offset = @resource_pages.current.offset
      @resources = []
      ## modified offset, limit approach through array rather than query
      (offset ... (offset + limit)).each do |i|
        break if @resources_no_limit[i].nil?
        @resources << @resources_no_limit[i]
      end
    end
    render :template => 'resource_managements/forecasts.rhtml', :layout => !request.xhr?
  end
  
  private
  def require_management
    return unless require_login
    unless User.current.allowed_to?(:manage_resources, nil, :global => true) || User.current.admin?
      render_403
      return false
    end
    true
  end
end
