/*
  :in-viewport selector----------------------------------------------------------
*/

(function(jQuery){jQuery.belowthefold=function(element,settings){var fold=jQuery(window).height()+jQuery(window).scrollTop();return fold<=jQuery(element).offset().top-settings.threshold;};jQuery.abovethetop=function(element,settings){var top=jQuery(window).scrollTop();return top>=jQuery(element).offset().top+jQuery(element).height()-settings.threshold;};jQuery.rightofscreen=function(element,settings){var fold=jQuery(window).width()+jQuery(window).scrollLeft();return fold<=jQuery(element).offset().left-settings.threshold;};jQuery.leftofscreen=function(element,settings){var left=jQuery(window).scrollLeft();return left>=jQuery(element).offset().left+jQuery(element).width()-settings.threshold;};jQuery.inviewport=function(element,settings){return!jQuery.rightofscreen(element,settings)&&!jQuery.leftofscreen(element,settings)&&!jQuery.belowthefold(element,settings)&&!jQuery.abovethetop(element,settings);};jQuery.extend(jQuery.expr[':'],{"below-the-fold":function(a,i,m){return jQuery.belowthefold(a,{threshold:0});},"above-the-top":function(a,i,m){return jQuery.abovethetop(a,{threshold:0});},"left-of-screen":function(a,i,m){return jQuery.leftofscreen(a,{threshold:0});},"right-of-screen":function(a,i,m){return jQuery.rightofscreen(a,{threshold:0});},"in-viewport":function(a,i,m){return jQuery.inviewport(a,{threshold:0});}});})(jQuery);

//------------------------------------------------------------------------------

function forecastsFixedHeader() {
  jQuery("#allocations_fixed_table_clone thead").html(jQuery('#allocations_fixed_table thead').html());
  var tmp1 = jQuery(".movable_table_container:first #weeks_header_holder");
  var tmp2 = jQuery(".movable_table_container:last #floating_tables_holder");
  
  setFixedHeaderWidth();
  tmp1.html(tmp2.html());
  jQuery(".movable_table_container:first #weeks_header_holder tbody").remove();
  
  setInterval(function(){
    tmp1.animate({left: tmp2.css("left")}, 0);
  }, 50);
}

function toggle_fixed_header(){
  jQuery(window).scroll(function(){
    var tables_container = jQuery("#forecasts_tables_container");
    if(jQuery(this).scrollLeft() > 0){
      jQuery("#fixed_header").css({'left': ((tables_container.position().left - jQuery(this).scrollLeft()) + 'px')});
    }else{
      jQuery("#fixed_header").css({'left': (tables_container.position().left + 'px')});
    }
    if(jQuery("#allocations_fixed_table thead").is(":in-viewport")){
      jQuery("#fixed_header").addClass("hide");
    }else{
      if(jQuery("#fixed_header").hasClass('hide')) jQuery("#fixed_header").removeClass("hide");
      object1 = jQuery(".movable_table_container:last");
      object2 = jQuery(".movable_table_container:first");
      object2.scrollLeft(object1.scrollLeft());
      object2.scrollTop(object1.scrollTop());
    }
  });
}

function resizeHeader(){
  jQuery("#fixed_header").width(jQuery('#forecasts_tables_container').innerWidth());
  setFixedHeaderWidth();
}

function synch_scroll_on_bar(){
  object1 = jQuery(".movable_table_container:last");
  object2 = jQuery(".movable_table_container:first");
  object1.scroll(function () {
    object2.scrollLeft(object1.scrollLeft());
    object2.scrollTop(object1.scrollTop());
  });
}


function synchRowHighlights(div) {
  var div_id = (div=="") ? "" : ("#"+div)
  jQuery(div_id+ " table tbody tr").live('mouseover', function(){
    var row = jQuery(this).closest('tr').prevAll().length;
    jQuery(div_id+ " table > tbody").find("tr:eq("+row+")").addClass("highlight");
  }).live('mouseout', function(){
    var row = jQuery(this).closest('tr').prevAll().length;
    jQuery(div_id+ " table > tbody").find("tr:eq("+row+")").removeClass("highlight");
  });
}

function allocationFixedHeader(){
  jQuery("#allocations_fixed_table_clone thead").html(jQuery('#allocations_fixed_table thead').html());
  setFixedHeaderWidth();
  var scrollable = jQuery("#mgt_allocations_scroll_pane");
  if(scrollable[0].scrollHeight > scrollable.innerHeight()){
    if(jQuery("#fixed_header").hasClass('hide')){
      jQuery("#fixed_header").removeClass('hide').css({width: jQuery("#mgt_allocations_table_container").width(),
                                          'top': (scrollable.position().top + 'px')});
    }
  }
  jQuery(window).scroll(function(){
    jQuery("#fixed_header").css({'top': ((scrollable.position().top - jQuery(this).scrollTop()) + 'px'),
                                                           'left': ((scrollable.position().left - jQuery(this).scrollLeft()) + 'px')});
  });
}

function setFixedHeaderWidth(){
  jQuery("#fixed_header .fixed_table_container").css({width: jQuery(".fixed_table_container:last").width()});
  jQuery("#fixed_header .movable_table_container").css({width: jQuery(".movable_table_container:last").width()});
  jQuery("#weeks_header_holder").css("width", jQuery("#floating_tables_holder").css("width"));
}
