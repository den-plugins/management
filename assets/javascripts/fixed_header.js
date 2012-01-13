/*
  :in-viewport selector----------------------------------------------------------
*/

(function(jQuery){jQuery.belowthefold=function(element,settings){var fold=jQuery(window).height()+jQuery(window).scrollTop();return fold<=jQuery(element).offset().top-settings.threshold;};jQuery.abovethetop=function(element,settings){var top=jQuery(window).scrollTop();return top>=jQuery(element).offset().top+jQuery(element).height()-settings.threshold;};jQuery.rightofscreen=function(element,settings){var fold=jQuery(window).width()+jQuery(window).scrollLeft();return fold<=jQuery(element).offset().left-settings.threshold;};jQuery.leftofscreen=function(element,settings){var left=jQuery(window).scrollLeft();return left>=jQuery(element).offset().left+jQuery(element).width()-settings.threshold;};jQuery.inviewport=function(element,settings){return!jQuery.rightofscreen(element,settings)&&!jQuery.leftofscreen(element,settings)&&!jQuery.belowthefold(element,settings)&&!jQuery.abovethetop(element,settings);};jQuery.extend(jQuery.expr[':'],{"below-the-fold":function(a,i,m){return jQuery.belowthefold(a,{threshold:0});},"above-the-top":function(a,i,m){return jQuery.abovethetop(a,{threshold:0});},"left-of-screen":function(a,i,m){return jQuery.leftofscreen(a,{threshold:0});},"right-of-screen":function(a,i,m){return jQuery.rightofscreen(a,{threshold:0});},"in-viewport":function(a,i,m){return jQuery.inviewport(a,{threshold:0});}});})(jQuery);

//------------------------------------------------------------------------------

function toggle_fixed_header(){
  jQuery(window).scroll(function(){
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

function scroll_fixed_header(){
  scrollable = jQuery(".movable_table_container:first #weeks_header_holder");
  scrollable.css({left: jQuery(".movable_table_container:last #floating_tables_holder").css("left")});
}

function synch_scroll_on_bar(){
  object1 = jQuery(".movable_table_container:last");
  object2 = jQuery(".movable_table_container:first");
  object1.scroll(function () {
    object2.scrollLeft(object1.scrollLeft());
    object2.scrollTop(object1.scrollTop());
  });
}

