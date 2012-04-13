function plot_skill_set(id, data) {
  var plot = jQuery.jqplot(id, data, {
    axes: {
      xaxis: {label: 'Weeks',renderer: jQuery.jqplot.DateAxisRenderer, tickOptions: {showMark: false, fontSize: '8pt'}},
      yaxis: {label: 'Skill Set Count',labelRenderer: jQuery.jqplot.CanvasAxisLabelRenderer, min: 0, max: 50}
    },
    legend: {show: false},
    cursor: {show: true, zoom: true},
    highlighter: {show: true, sizeAdjust: 7.5}
  });
  //jQuery('.button-reset').click(function() { plot.resetZoom() });
}

function plot_billability_forecast(container_id, data) {
  charts.billability_forecast = function(id) {
    jQuery.jqplot(id, data, {
      axes: {
        xaxis: {label: 'Weeks', autoscale: true, renderer: jQuery.jqplot.DateAxisRenderer, tickOptions: {showMark: false, fontSize: '8pt', formatString: '%m/%d/%y'}},
        yaxis: {label: 'Total Allocation (%)',labelRenderer: jQuery.jqplot.CanvasAxisLabelRenderer, min: 0}
      },
      legend: {show: false},
      cursor: {show: true, zoom: true},
      highlighter: {show: true, sizeAdjust: 7.5}
    });
  };
  charts.billability_forecast(container_id);
}


function toggle_multi_select(id){
  select = $(id);
  if (select.multiple == true) {
      select.multiple = false;
  } else {
      select.multiple = true;
  }
}

var charts = {};

jQuery(document).ready(function($) {
  jQuery('.zoom').live('click', function(e) {
    e.preventDefault();
    var chartTitle = $(this).parents('.box').find('h3').text().trim(),
      chartName = this.id.replace('zoom_', '');
    if(charts.hasOwnProperty(chartName)) {
      jQuery.facebox('<h1 id="zoom_chart_title"></h1> <div id="zoom_chart"></div>');
      jQuery('#zoom_chart_title').text(chartTitle);
      if(chartName == 'line_graph'){
        sel_skill = $(this).parents('.box').find('select').val();
        if(sel_skill != "All"){
          jQuery('#zoom_chart_title').text(chartTitle + " (" + sel_skill + ")");
        }
      }
      charts[chartName]('zoom_chart');
    }
  });
});
