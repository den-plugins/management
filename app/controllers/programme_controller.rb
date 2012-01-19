class ProgrammeController < ApplicationController
  helper :sort
  include SortHelper

  def index
    sort_init 'name', 'asc'
    sort_update({"name" =>  "name", "proj_manager" => "#{User.table_name}.firstname"})

    @projects = Project.find(:all, :include => [:manager], :order => sort_clause)
    @devt_projects_sorted = @projects.select(&:development?)
    @devt_projects = @devt_projects_sorted.sort_by {|s| s.name.downcase }

    @fixed_cost_projects = @projects.select(&:fixed_cost?)
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
  
  private
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
