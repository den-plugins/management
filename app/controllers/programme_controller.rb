class ProgrammeController < ApplicationController
  helper :sort
  include SortHelper

  def index
    sort_init 'name', 'asc'
    sort_update({"name" =>  "name", "proj_manager" => "#{User.table_name}.firstname"})

    @projects = Project.find(:all, :include => [:manager], :order => sort_clause)
    @devt_projects = @projects.select(&:development?)

    @fixed_cost_projects = @projects.select(&:fixed_cost?)
    @billabilities = {}
    @devt_projects.each {|p| load_billability_file p }

    load_fixed_cost_file
    render :template => 'programme/index', :layout => !request.xhr?
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
