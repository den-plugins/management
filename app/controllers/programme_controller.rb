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
    @billabilities = {}
    @devt_projects.each {|p| load_billability_file p }

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
  def load_billability_file(project)
    if File.exists?("#{RAILS_ROOT}/config/billability.yml")
      if file = YAML.load(File.open("#{RAILS_ROOT}/config/billability.yml"))
        if billability = file["billability_#{project.id}"]
          @billabilities[project.id] = billability
        end
      end
    end
  end

  def load_fixed_cost_file
   @fixed_costs = if File.exists?("#{RAILS_ROOT}/config/fixed_cost.yml")
      YAML.load(File.open("#{RAILS_ROOT}/config/fixed_cost.yml"))
    else
      {}
    end
  end
end
