class ProgrammeController < ApplicationController
  helper :project_schedule

  def index
    @devt_projects = Project.find(:all, :order => 'name ASC').select(&:development?)
    
    @billabilities = {}
    #load billability file (pm_dashboard)
    @devt_projects.each {|p| load_billability_file p }
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

end
