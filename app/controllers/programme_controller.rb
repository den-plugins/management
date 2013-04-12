class ProgrammeController < ApplicationController
  helper :sort
  helper :efficiency
  include SortHelper
  include EfficiencyHelper

  menu_item :dashboard, :only => :index
  menu_item :interactive, :only => :interactive
  menu_item :pre_sales, :only => :pre_sales
  menu_item :maintenance, :only => :maintenance
  menu_item :outstanding_issues, :only => :outstanding_issues
  menu_item :outstanding_risks, :only => :outstanding_risks

  before_filter :require_pmanagement

  def index
    sort_init 'name', 'asc'
    sort_update({"name" => "name", "proj_manager" => "#{User.table_name}.firstname"})
    @all_projects = params[:all_projects] ? params[:all_projects] : false

    @header = "Programme Dashboard"
    @projects = @all_projects || !@all_projects.blank? ? Project.find(:all, :include => [:manager],
                                                                      :conditions => ["projects.status = ?", Project::STATUS_ACTIVE],
                                                                      :order => sort_clause) :
        Project.find(:all, :include => [:manager],
                     :conditions => ["projects.status = ?", Project::STATUS_ACTIVE],
                     :order => sort_clause).reject { |x| x.closed? }
    @devt_projects_sorted = @projects.select(&:in_programme?)
    @devt_projects = @devt_projects_sorted

    @fixed_cost_projects = @devt_projects.select(&:fixed_cost?)
    @t_and_m_projects = @devt_projects.select(&:t_and_m?)

    load_billability_file
    load_fixed_cost_file

    if request.xhr?
      render :update do |page|
        page.replace_html :programme_project_health, :partial => "programme/project_health"
        page.replace_html :programme_project_schedule, :partial => "programme/charts/project_schedule"
        page.replace_html :programme_fixed_cost_projects, :partial => "programme/charts/fixed_cost_projects"
        page.replace_html :programme_t_and_m_projects, :partial => "programme/charts/t_and_m_projects"
      end
    else
      render :template => 'programme/index'
    end
  end

  def interactive
    sort_init 'name', 'asc'
    sort_update({"name" => "name", "proj_manager" => "#{User.table_name}.firstname"})
    @all_projects = params[:all_projects] ? params[:all_projects] : false

    @header = "Interactive Programme Dashboard"
    @projects = @all_projects || !@all_projects.blank? ? Project.find(:all, :include => [:manager],
                                                                      :conditions => ["projects.status = ?", Project::STATUS_ACTIVE],
                                                                      :order => sort_clause) :
        Project.find(:all, :include => [:manager],
                     :conditions => ["projects.status = ?", Project::STATUS_ACTIVE],
                     :order => sort_clause).reject { |x| x.closed? }
    @devt_projects_sorted = @projects.select(&:dev_interactive?)
    @devt_projects = @devt_projects_sorted

    @fixed_cost_projects = @devt_projects.select(&:fixed_cost?)
    @t_and_m_projects = @devt_projects.select(&:t_and_m?)

    load_billability_file
    load_fixed_cost_file

    if request.xhr?
      render :update do |page|
        page.replace_html :programme_project_health, :partial => "programme/project_health"
        page.replace_html :programme_project_schedule, :partial => "programme/charts/project_schedule"
        page.replace_html :programme_fixed_cost_projects, :partial => "programme/charts/fixed_cost_projects"
        page.replace_html :programme_t_and_m_projects, :partial => "programme/charts/t_and_m_projects"
      end
    else
      render :template => 'programme/index'
    end
  end

  def pre_sales
    sort_init 'subject', 'asc'
    sort_update({"subject" => "subject", "proj_manager" => "#{User.table_name}.firstname", "category" => "#{IssueCategory.table_name}.name", "custom-issue-projected_start_date" => "custom-issue-projected_start_date"})

    @header = "Pre-Sales Programme Dashboard"
    @pre_sales = Project.find(:first, :conditions => "name = 'Exist Pre-Sales'")
    @features = @pre_sales.issues.open.find(:all, full_sort_clause(:include => [:assigned_to, :tracker, :category],
                                                                   :conditions => "trackers.name = 'Feature'")) if @pre_sales

    if request.xhr?
      render :update do |page|
        page.replace_html :programme_project_health, :partial => "programme/pre_sales/project_health"
      end
    else
      render :template => 'programme/pre_sales'
    end
  end

  def maintenance
    sort_init 'name', 'asc'
    sort_update({"name" => "name", "proj_manager" => "#{User.table_name}.firstname"})

    @header = "Projects in Warranty Period Programme Dashboard"
    @projects = Project.find(:all, :include => [:manager],
                             :conditions => ["projects.status = ?", Project::STATUS_ACTIVE],
                             :order => sort_clause)
    @devt_projects_sorted = @projects.select(&:in_warranty?)
    @devt_projects = @devt_projects_sorted.sort_by { |s| s.name.downcase }
    @issues = Hash.new
    @devt_projects_sorted.each do |project|
      @issues[["#{project}", project.identifier]] = project.pm_dashboard_issues.find(:all, :conditions => ["impact > ?", 2])
    end

    @fixed_cost_projects = @devt_projects.select(&:fixed_cost?).sort_by { |s| s.name.downcase }
    @t_and_m_projects = @devt_projects.select(&:t_and_m?).sort_by { |s| s.name.downcase }

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

  def outstanding_issues
    @header = "Outstanding Issues"
    @projects = Project.find(:all, :include => [:manager],
                            :conditions => ["projects.status = ?", Project::STATUS_ACTIVE])
    @high_impact_issues = Hash.new
    @devt_projects = @projects.sort_by { |s| s.name.downcase }

    @devt_projects.each do |project|
      @high_impact_issues["#{project}"] = project.pm_dashboard_issues.find(:all, :conditions => ["impact > ?", 2]).reject {|x| !x.date_close.nil?}
    end

    if request.xhr?
      render :update do |page|
        page.replace_html :programme_project_health, :partial => "programme/project_health"
      end
    else
      render :template => 'programme/outstanding_issues'
    end
  end

  def outstanding_risks
    @header = "Outstanding Risks"
    @projects = Project.find(:all, :include => [:manager],
                             :conditions => ["projects.status = ?", Project::STATUS_ACTIVE])
    @risk_issues = Hash.new
    @devt_projects = @projects.sort_by { |s| s.name.downcase }

    @devt_projects.each do |project|
      @risk_issues["#{project}"] = project.risks.find(:all, :conditions => ["status <> ? AND final_risk_rating > ? ", 'C', 15])
    end

    if request.xhr?
      render :update do |page|
        page.replace_html :programme_project_health, :partial => "programme/project_health"
      end
    else
      render :template => 'programme/outstanding_risks'
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
