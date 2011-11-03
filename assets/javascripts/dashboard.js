function plot_resource_allocation(id, data, series) {
  var plot = jQuery.jqplot(id, data, {
    axes: {
      xaxis: {label: 'Weeks', renderer: jQuery.jqplot.DateAxisRenderer, tickOptions: {showMark: false, fontSize: '8pt'}},
      yaxis: {label: "Allocation Count", labelRenderer: jQuery.jqplot.CanvasAxisLabelRenderer, min: 0, max: 5}
    },
    legend: {show: false},
    cursor: {show: true, zoom: true},
    highlighter: {show: true, sizeAdjust: 7.5}
  });
  //jQuery('.button-reset').click(function() { plot.resetZoom() });
}

function plot_forecast_by_skill(id, data) {
  var plot = jQuery.jqplot(id, data, {
    legend: {show: true},
    cursor: {show: true, zoom: true},
    highlighter: {show: true, sizeAdjust: 7.5},
    axes: {
      xaxis: {label: 'Weeks'}
    }
  });
  //jQuery('.button-reset').click(function() { plot.resetZoom() });
}

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

