class ProgrammeController < ApplicationController
  helper :project_schedule

  def index
    @projects = Project.find(:all, :order => 'name ASC')
    @devt_projects = @projects.select(&:development?)
    @fixed_cost_projects = @projects.select(&:fixed_cost?)
    
    @billabilities = {}
    #load billability file (pm_dashboard)
    @devt_projects.each {|p| load_billability_file p }
    load_fixed_cost_file
    render :template => 'programme/index'
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
