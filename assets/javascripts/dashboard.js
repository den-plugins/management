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

