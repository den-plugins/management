class ForecastBillableJob < Struct.new(:from, :to, :selection, :key, :user_ids)
  include Delayed::ScheduledJob
  include ResourceManagementsHelper
  include CostMonitoringHelper
  include ResourceCostsHelper
  require 'json'

  run_every(Time.parse("12am") + 1.day)
 cge
 
  def perform
    users = User.find(:all, :conditions => "id in (#{user_ids.join(',')})")
    now = Time.now.strftime('%b %d, %Y %I:%M %p')
    if FileTest.exists?("#{RAILS_ROOT}/config/forecast_billable.json")
      data = (file=JSON.parse(File.read("#{RAILS_ROOT}/config/forecast_billable.json"))) ? file : {}
    else
      data = {}
    end
    fb = data.merge({selection.downcase.gsub(' ', '_') => (forecast_billable_data(users, (from .. to)) + [now] )}).to_json
    puts fb.inspect
    File.open("#{RAILS_ROOT}/config/forecast_billable.json","w") do |f|
      f.write(fb)
    end
  end

end
