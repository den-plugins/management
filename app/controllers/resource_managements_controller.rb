class ResourceManagementsController < ApplicationController

  menu_item :dashboard
  menu_item :allocations, :only => :allocations

  def index
  end

  def get
  end

  def allocations

  end
end
