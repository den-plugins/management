class ProgrammeController < ApplicationController
  helper :sort
  include SortHelper
  
  menu_item :dashboard, :only => :index
  menu_item :interactive, :only => :interactive
  menu_item :pre_sales, :only => :pre_sales

  before_filter :require_pmanagement
  
  def index
    sort_init 'name', 'asc'
    sort_update({"name" =>  "name", "proj_manager" => "#{User.table_name}.firstname"})
    
    @header = "Engineering Programme Dashboard"
    @projects = Project.find(:all, :include => [:manager],
                             :conditions => ["projects.status = ?", Project::STATUS_ACTIVE],
                             :order => sort_clause)
    @devt_projects_sorted = @projects.select(&:development?)
    @devt_projects = @devt_projects_sorted.sort_by {|s| s.name.downcase }

    @fixed_cost_projects = @projects.select(&:fixed_cost?).sort_by {|s| s.name.downcase }
    @t_and_m_projects = @projects.select(&:t_and_m?).sort_by {|s| s.name.downcase }
    
    load_billability_file
    load_fixed_cost_file
    
    if request.xhr?
      render :update do |page|
        page.replace_html :programme_project_health, :partial => "programme/project_health"
      end
    else
      render :template => 'programme/index'
    end
  end
  
  def interactive
    sort_init 'name', 'asc'
    sort_update({"name" =>  "name", "proj_manager" => "#{User.table_name}.firstname"})
    
    @header = "Interactive Programme Dashboard"
    @projects = Project.find(:all, :include => [:manager],
                             :conditions => ["projects.status = ?", Project::STATUS_ACTIVE],
                             :order => sort_clause)
    @devt_projects_sorted = @projects.select(&:dev_interactive?)
    @devt_projects = @devt_projects_sorted.sort_by {|s| s.name.downcase }

    @fixed_cost_projects = @projects.select(&:fixed_cost?).sort_by {|s| s.name.downcase }
    @t_and_m_projects = @projects.select(&:t_and_m?).sort_by {|s| s.name.downcase }
    
    load_billability_file
    load_fixed_cost_file
    
    if request.xhr?
      render :update do |page|
        page.replace_html :programme_project_health, :partial => "programme/project_health"
      end
    else
      render :template => 'programme/index'
    end
  end

  def pre_sales
    sort_init 'name', 'asc'
    sort_update({"name" =>  "name", "proj_manager" => "#{User.table_name}.firstname"})
    
    @header = "Pre-sales Programme Dashboard"
    @projects = Project.find(:all, :include => [:manager],
                             :conditions => ["projects.status = ?", Project::STATUS_ACTIVE],
                             :order => sort_clause)
    @devt_projects_sorted = @projects.select(&:pre_sales?)
    @devt_projects = @devt_projects_sorted.sort_by {|s| s.name.downcase }

#    @fixed_cost_projects = @projects.select(&:fixed_cost?).sort_by {|s| s.name.downcase }
#    @t_and_m_projects = @projects.select(&:t_and_m?).sort_by {|s| s.name.downcase }
    
#    load_billability_file
#    load_fixed_cost_file
    
    if request.xhr?
      render :update do |page|
        page.replace_html :programme_project_health, :partial => "programme/project_health"
      end
    else
      render :template => 'programme/index'
    end
  end

  private
  def require_pmanagement
    return unless require_login
    unless User.current.allowed_to?(:view_programme_dashboard, nil, :global => true) || User.current.admin?
      render_403
      return false
    end
    true
  end
  
  def load_billability_file
    @billabilities = if File.exists?("#{RAILS_ROOT}/config/billability.yml")
      YAML.load(File.open("#{RAILS_ROOT}/config/billability.yml")) || {}
    else
      {}
    end
  end

  def load_fixed_cost_file
    @fixed_costs = if File.exists?("#{RAILS_ROOT}/config/fixed_cost.yml")
      YAML.load(File.open("#{RAILS_ROOT}/config/fixed_cost.yml")) || {}
    else
      {}
    end
  end
end
