// http://jqueryui.com/demos/slider/#side-scroll //

function enableHorizontalSlider() {
  var scrollPane = jQuery( ".movable_table_container:last"),
	scrollContent = jQuery( "#floating_tables_holder"),
	scrollContent2 = jQuery("#fixed_header .movable_table_container #weeks_header_holder");

  var diff = scrollContent.width() - scrollPane.width();
  if (diff > 0) {
    scrollPane.css("overflow", "hidden");
		var scrollbar = jQuery( "#slider-horizontal" ).slider({
			slide: function( event, ui ) {
					scrollContent.css( "margin-left", Math.round(ui.value / 100 * ( scrollPane.width() - scrollContent.width())) + "px" );
					scrollContent2.css('margin-left', scrollContent.css('margin-left'));
			},
			change: function( event, ui ) {
					scrollContent.css( "margin-left", Math.round(ui.value / 100 * ( scrollPane.width() - scrollContent.width())) + "px" );
					scrollContent2.css('margin-left', scrollContent.css('margin-left'));
			}
		});
		
		var handleHelper = scrollbar.find( ".ui-slider-handle" )
		.append( "<span class='ui-icon'></span>" )
		.wrap( "<div class='ui-handle-helper-parent'></div>" ).parent();
		
		//size slider
		function sizeSlider() {
       jQuery("#slider-horizontal").show().css({left: jQuery(".fixed_table_container:last").width(), width: scrollPane.width()});
		}
		
		setTimeout( sizeSlider, 10 );//safari wants a timeout
		
		//size scrollbar and handle proportionally to scroll distance
		function sizeScrollbar() {
			var remainder = scrollContent.width() - scrollPane.width();
			var proportion = remainder / scrollContent.width();
			var handleSize = scrollPane.width() - ( proportion * scrollPane.width() );
			scrollbar.find( ".ui-slider-handle" ).css({	width: handleSize,	 "margin-left": -handleSize / 2 });
			handleHelper.width("").width(scrollbar.width() - handleSize);
		}
		
		//reset slider value based on scroll content position
		function resetValue() {
			var remainder = scrollPane.width() - scrollContent.width();
			var leftVal = scrollContent.css("margin-left") === "auto" ? 0 : parseInt(scrollContent.css("margin-left") );
			var percentage = Math.round( leftVal / remainder * 100 );
			scrollbar.slider("value", percentage);
		}
		
		//if the slider is 100% and window gets larger, reveal content
		function reflowContent() {
				var showing = scrollContent.width() + parseInt( scrollContent.css( "margin-left" ), 10 );
				var gap = scrollPane.width() - showing;
				if ( gap > 0 ) {
					scrollContent.css( "margin-left", parseInt( scrollContent.css( "margin-left" ), 10 ) + gap );
					scrollContent2.css('margin-left', scrollContent.css('margin-left'));
				}
		}
		
		//change handle position on window resize
		jQuery(window).resize(function() {
		  sizeSlider();
			resetValue();
			sizeScrollbar();
			reflowContent();
			setFixedHeaderWidth();
		});
		//init scrollbar size
		setTimeout( sizeScrollbar, 10 );//safari wants a timeout
  }
}


function enableVerticalSlider() {
  var scrollPane = jQuery( "#mgt_allocations_table_container"),
	scrollContent = jQuery( ".movable_table_container");

  var diff = jQuery(".movable_table_container").height() - jQuery("#mgt_allocations_table_container").height();
  if (diff > 0) {
    jQuery("#slider-vertical").show().css({height: scrollPane.height()});
		var scrollbar = jQuery( "#slider-vertical" ).slider({
			slide: function( event, ui ) {
					scrollContent.css( "margin-top", Math.round(ui.value / 100 * ( scrollPane.height() - scrollContent.height())) + "px" );
			},
			change: function( event, ui ) {
					scrollContent.css( "margin-top", Math.round(ui.value / 100 * ( scrollPane.height() - scrollContent.height())) + "px" );
			},
			orientation: 'vertical',
			min: 0,
			max: 100
		});
		
		var handleHelper = scrollbar.find( ".ui-slider-handle" )
		.append( "<span class='ui-icon'></span>" )
		.wrap( "<div class='ui-handle-helper-parent'></div>" ).parent();
		
		scrollPane.css( "overflow", "hidden" );
		
		//size scrollbar and handle proportionally to scroll distance
		function sizeScrollbar() {
			var remainder = scrollContent.height() - scrollPane.height();
			var proportion = remainder / scrollContent.height();
			var handleSize = scrollPane.height() - ( proportion * scrollPane.height() );
			scrollbar.find( ".ui-slider-handle" ).css({
				height: handleSize,
				"margin-top": -handleSize / 2
			});
			handleHelper.height( "" ).height( scrollbar.height() - handleSize );
		}
		
		//reset slider value based on scroll content position
		function resetValue() {
			var remainder = scrollPane.height() - scrollContent.height();
			var topVal = scrollContent.css( "margin-top" ) === "auto" ? 0 :
				parseInt( scrollContent.css( "margin-top" ) );
			var percentage = Math.round( topVal / remainder * 100 );
			scrollbar.slider( "value", percentage );
		}
		
		//if the slider is 100% and window gets larger, reveal content
		function reflowContent() {
				var showing = scrollContent.height() + parseInt( scrollContent.css( "margin-top" ), 10 );
				var gap = scrollPane.height() - showing;
				if ( gap > 0 ) {
					scrollContent.css( "margin-top", parseInt( scrollContent.css( "margin-top" ), 10 ) + gap );
				}
		}
		
		//change handle position on window resize
		jQuery( window ).resize(function() {
		  sizeSlider();
			resetValue();
			sizeScrollbar();
			reflowContent();
		});
		
		//init scrollbar size
		setTimeout(sizeScrollbar, 10);  //safari wants a timeout
  }
}
