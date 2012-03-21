class ForecastBillableJob < Struct.new(:from, :to, :selection, :data, :user_ids)
  include ResourceManagementsHelper
  include CostMonitoringHelper
  include ResourceCostsHelper

  def perform
    users = User.find(:all, :conditions => "id in (#{user_ids.join(',')})")
    fb = data.merge({selection.downcase.gsub(' ', '_') => forecast_billable_data(users, (from .. to))}).to_json
    File.open("#{RAILS_ROOT}/config/forecast_billable.json","w") do |f|
      f.write(fb)
    end
  end

end
