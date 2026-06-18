// JavaScript Document
jQuery(document).ready(function($) {
	
	// TABLE OF CONTENT
	
	// JqueryTools
	// PrettyPhoto Setup
	// Alert Box Close
	// Portfolio No filter - Change layout
	// Post % Portfolio Hover Effect
	// Searchbar
	// Contactform Post
	// Tab & Accordion
	// FlexSlider
	// Portfolio Filter
	// Mobile Menu
	// Twitter
	
	
/*Jquery Tools :: http://jquerytools.org/
-------------------------------------------------*/

(function(a){a.tools=a.tools||{version:"dev"},a.tools.tabs={conf:{tabs:"a",current:"current",onBeforeClick:null,onClick:null,effect:"default",initialIndex:0,event:"click",rotate:!1,slideUpSpeed:400,slideDownSpeed:400,history:!1},addEffect:function(a,c){b[a]=c}};var b={"default":function(a,b){this.getPanes().hide().eq(a).show(),b.call()},fade:function(a,b){var c=this.getConf(),d=c.fadeOutSpeed,e=this.getPanes();d?e.fadeOut(d):e.hide(),e.eq(a).fadeIn(c.fadeInSpeed,b)},slide:function(a,b){var c=this.getConf();this.getPanes().slideUp(c.slideUpSpeed),this.getPanes().eq(a).slideDown(c.slideDownSpeed,b)},ajax:function(a,b){this.getPanes().eq(0).load(this.getTabs().eq(a).attr("href"),b)}},c,d;a.tools.tabs.addEffect("horizontal",function(b,e){if(!c){var f=this.getPanes().eq(b),g=this.getCurrentPane();d||(d=this.getPanes().eq(0).width()),c=!0,f.show(),g.animate({width:0},{step:function(a){f.css("width",d-a)},complete:function(){a(this).hide(),e.call(),c=!1}}),g.length||(e.call(),c=!1)}});function e(c,d,e){var f=this,g=c.add(this),h=c.find(e.tabs),i=d.jquery?d:c.children(d),j;h.length||(h=c.children()),i.length||(i=c.parent().find(d)),i.length||(i=a(d)),a.extend(this,{click:function(c,d){var i=h.eq(c);typeof c=="string"&&c.replace("#","")&&(i=h.filter("[href*="+c.replace("#","")+"]"),c=Math.max(h.index(i),0));if(e.rotate){var k=h.length-1;if(c<0)return f.click(k,d);if(c>k)return f.click(0,d)}if(!i.length){if(j>=0)return f;c=e.initialIndex,i=h.eq(c)}if(c===j)return f;d=d||a.Event(),d.type="onBeforeClick",g.trigger(d,[c]);if(!d.isDefaultPrevented()){b[e.effect].call(f,c,function(){j=c,d.type="onClick",g.trigger(d,[c])}),h.removeClass(e.current),i.addClass(e.current);return f}},getConf:function(){return e},getTabs:function(){return h},getPanes:function(){return i},getCurrentPane:function(){return i.eq(j)},getCurrentTab:function(){return h.eq(j)},getIndex:function(){return j},next:function(){return f.click(j+1)},prev:function(){return f.click(j-1)},destroy:function(){h.unbind(e.event).removeClass(e.current),i.find("a[href^=#]").unbind("click.T");return f}}),a.each("onBeforeClick,onClick".split(","),function(b,c){a.isFunction(e[c])&&a(f).bind(c,e[c]),f[c]=function(b){b&&a(f).bind(c,b);return f}}),e.history&&a.fn.history&&(a.tools.history.init(h),e.event="history"),h.each(function(b){a(this).bind(e.event,function(a){f.click(b,a);return a.preventDefault()})}),i.find("a[href^=#]").bind("click.T",function(b){f.click(a(this).attr("href"),b)}),location.hash&&e.tabs=="a"&&c.find("[href="+location.hash+"]").length?f.click(location.hash):(e.initialIndex===0||e.initialIndex>0)&&f.click(e.initialIndex)}a.fn.tabs=function(b,c){var d=this.data("tabs");d&&(d.destroy(),this.removeData("tabs")),a.isFunction(c)&&(c={onBeforeClick:c}),c=a.extend({},a.tools.tabs.conf,c),this.each(function(){d=new e(a(this),b,c),a(this).data("tabs",d)});return c.api?d:this}})(jQuery);
	

/*PrettyPhoto Setup
-------------------------------------------------*/
 
jQuery("a[rel^='prettyPhoto']").prettyPhoto({animationSpeed:'slow',slideshow:false,overlay_gallery: false,social_tools:false,deeplinking:false});
 
/*Alert Box Close
-------------------------------------------------*/
	
$('.closebox').click(function() { $(this).parent('div').slideUp();});

/*Form Validate
-------------------------------------------------*/

jQuery("#contactform").validate(); /*Contactform Validate*/
jQuery("#commentform").validate(); /*Commentform Validate*/


/*Portfolio No filter - Change layout
-------------------------------------------------*/

//default Portfolio Layout
$('#porfolionf li.element').children('.three').removeClass('three').addClass('four');
$('#porfolionf li.element').children('.four').removeClass('four').addClass('four');
$('#porfolionf li.element').children('.six').removeClass('six').addClass('four');

//Changer button opacity
$('.alayout').animate({opacity:0.5});	

//Changer
$('#changer').click(function () {
		
	$(this).animate({opacity:0.5})	
	$('#changer3 , #changer2').animate({opacity:1})
	
	$('#porfolionf li.element').children('.three').removeClass('three').addClass('four');
	$('#porfolionf li.element').children('.six').removeClass('six').addClass('four');
	
});
		
//Changer2
$('#changer2').click(function () {
	
	$(this).animate({opacity:0.5})
	$('#changer , #changer3').animate({opacity:1})	
	
	$('#porfolionf li.element').children('.four').removeClass('four').addClass('three');
	$('#porfolionf li.element').children('.six').removeClass('six').addClass('three');

});

//Changer3		
$('#changer3').click(function () {
	
		$(this).animate({opacity:0.5})
		$('#changer , #changer2').animate({opacity:1})	
		
		$('#porfolionf li.element').children('.four').removeClass('four').addClass('six');
		$('#porfolionf li.element').children('.three').removeClass('three').addClass('six');

});
		
/* Post % Portfolio Hover Effect
-------------------------------------------------*/
	
$('.blog-thumb-image a, .blog-item-image a , .recentportfolio li , .recentportfolio li a , .portfolio-thumb-image a , .lightbox').hover(function () {
		
			$(this).children('img').stop().animate({opacity:0.2});
				
		},function () {$(this).children('img').stop().animate({opacity:1});
		
});


/* Searchbar
-------------------------------------------------*/
	
$('input.searchinput').hover(function () {
		
	$('input.searchinput').stop().animate({width:100,paddingLeft:60,paddingRight:10,});
		
	},function () {
		
		$('input.searchinput').val('');
		$('input.searchinput').stop().animate({width:60,paddingLeft:0,paddingRight:0});
		
});


/* Contactform Post
-------------------------------------------------*/

$('form#contactform').submit(function() {
	var hasError = false;
	
		$('.required').each(function() {
				if($.trim($(this).val()) == '') {
					hasError = true;
				}
			});

		if(!hasError) {
			var formInput = $(this).serialize();
			$.post('contacts.php',formInput, function(data){
				$('form#contactform').slideUp("fast", function() {				   
					$(this).before('<div class="b_green">Yay! If you see this message box, that means everything went good.</div>');
				});
			});
		}
		
		return false;	
});

	
/* Tab & Accordion
-------------------------------------------------*/

$(function() {
      $("ul.tabs").tabs("> .pane" ,  {effect: 'fade'});
});
	
$(function() {
 	 $(".accordion , .accordion-v").tabs(".pane", {tabs: 'h2', effect: 'slide'});
});
 
/* FlexSlider
-------------------------------------------------*/

$(window).load(function() {

	$('.sliderblog').flexslider({		
			controlNav: true,
			pauseOnHover: true,
			slideshowSpeed: 5000,
			start: function(slider) {
			slider.removeClass('loading');} 
	});
			
	$('.common').flexslider({
			controlNav: true,
			pauseOnHover: true,
			slideshowSpeed: 5000, 
			start: function(slider) {
			slider.removeClass('loading');}
	});
			
	$('.slidetestimonials').flexslider({
			controlNav: false,
			directionNav: false,
			pauseOnHover: true,
			slideshowSpeed: 3000,
			start: function(slider) {
			slider.removeClass('loading');} 
	});
		  
	$('#slider3').flexslider({		
			directionNav: false,
			slideshow: false,   
			animation: "slide",
	    	animationLoop: false,
			itemWidth: 155,
	    	itemMargin: 0,
	    	minItems: 1,
	    	maxItems: 6,
			start: function(slider) {
			slider.removeClass('loading');} });
	
	$('#slider2').flexslider({
			directionNav: false,
			slideshow: false, 
			start: function(slider) {
			slider.removeClass('loading');}
	});
		  
	$('#slider1').flexslider({
			controlNav: false,
			pauseOnHover: true,
			slideshowSpeed: 5000,
			
		  start: function(slider) {
			slider.removeClass('loading');
	        $('.caption-title').animate({left:0},500);
			$('.caption-subtitle').animate({left:0},600);
			 
			$('.caption-title2').animate({right:0},500);
			$('.caption-subtitle2').animate({right:0},600);
	      },
		   before: function(slider) {
	        $('.caption-title').animate({left:100,opacity:0},500);
			$('.caption-subtitle').animate({left:100,opacity:0},600);
			
			$('.caption-title2').animate({right:100,opacity:0},500);
			$('.caption-subtitle2').animate({right:100,opacity:0},600);
	      },
	      after: function(slider) {
	        $('.caption-title').animate({left:0,opacity:1},500);
			$('.caption-subtitle').animate({left:0,opacity:0.8},600);
			
			$('.caption-title2').animate({right:0,opacity:1},500);
			$('.caption-subtitle2').animate({right:0,opacity:0.8},600);
	      }
	});
		
	$('.slider-wrapper').find('.flex-direction-nav li a').animate({ opacity: 0 }, 0);
	$('.sliderblog').find('.flex-direction-nav li a').animate({ opacity: 0 }, 0);
	
	$('.slider-wrapper , .sliderblog').hover(function () {
		
		$(this).find('.flex-direction-nav li a').animate({ opacity: 1 }, 500);
		
		}, function () {
			
		$(this).find('.flex-direction-nav li a').animate({ opacity: 0 }, 500);
			
	});
});


/* Portfolio Filter
-------------------------------------------------*/

$(window).load(function(){
  	  
	 $(function(){
	      
	      var $filtercontent = $('#project');
	
	      $filtercontent.isotope({
	        itemSelector : 'li.element'
	      });
	     
	      var $optionSets = $('#options .option-set'),
	          $optionLinks = $optionSets.find('a');
			  
			  $('#project').isotope({   layoutMode : 'fitRows'});
			 		
	      $optionLinks.click(function(){
	        var $this = $(this);
	        // don't proceed if already selected
	        if ( $this.hasClass('selected') ) {
	          return false;
	        }
	        var $optionSet = $this.parents('.option-set');
	        $optionSet.find('.selected').removeClass('selected');
	        $this.addClass('selected');
	  
	        // make option object dynamically, i.e. { filter: '.my-filter-class' }
	        var options = {},
	            key = $optionSet.attr('data-option-key'),
	            value = $this.attr('data-option-value');
	        // parse 'false' as false boolean
	        value = value === 'false' ? false : value;
	        options[ key ] = value;
	        if ( key === 'layoutMode' && typeof changeLayoutMode === 'function' ) {
	          // changes in layout modes need extra logic
	          changeLayoutMode( $this, options )
	        } else {
	          // otherwise, apply new options
	          $filtercontent.isotope( options );
	        }
	        
	        return false;
	      });
	    });
});


/* Mobile Menu
-------------------------------------------------*/
	
	jQuery(function(){
			jQuery('ul.menu').superfish();
		});
		
		  // DOM ready
	 $(function() {
	   
      // Create the dropdown base
      $("<select />").appendTo(".main-menu");
      
      // Create default option "Go to..."
      $("<option />", {
         "selected": "selected",
         "value"   : "",
         "text"    : "Go to..."
      }).appendTo(".main-menu select");
      
      // Populate dropdown with menu items
      $(".mobile-main-menu a").each(function() {
       var el = $(this);
       $("<option />", {
           "value"   : el.attr("href"),
           "text"    : el.text()
       }).appendTo(".main-menu select");
      });
      
	   // To make dropdown actually work
	   // To make more unobtrusive: http://css-tricks.com/4064-unobtrusive-page-changer/
      $(".mobile-main-menu select").change(function() {
        window.location = $(this).find("option:selected").val();
      });
	 
	 });
	
});


/* Twitter
-------------------------------------------------*/
		
function twitter_f(twitters) {
  var statusHTML = [];
  for (var i=0; i<twitters.length; i++){
    var username = twitters[i].user.screen_name;
    var status = twitters[i].text.replace(/((https?|s?ftp|ssh)\:\/\/[^"\s\<\>]*[^.,;'">\:\s\<\>\)\]\!])/g, function(url) {
      return '<a href="'+url+'">'+url+'</a>';
    }).replace(/\B@([_a-z0-9]+)/ig, function(reply) {
      return  reply.charAt(0)+'<a href="http://twitter.com/'+reply.substring(1)+'">'+reply.substring(1)+'</a>';
    });
    statusHTML.push('<li><span>'+status+'</span> <a style="font-size:75%; color:#444; text-decoration:none; display:block;" href="http://twitter.com/'+username+'/statuses/'+twitters[i].id_str+'">'+relative_time(twitters[i].created_at)+'</a></li>');
  }
  return statusHTML.join('');
}

function relative_time(time_value) {
  var values = time_value.split(" ");
  time_value = values[1] + " " + values[2] + ", " + values[5] + " " + values[3];
  var parsed_date = Date.parse(time_value);
  var relative_to = (arguments.length > 1) ? arguments[1] : new Date();
  var delta = parseInt((relative_to.getTime() - parsed_date) / 1000);
  delta = delta + (relative_to.getTimezoneOffset() * 60);

  if (delta < 60) {
    return 'less than a minute ago';
  } else if(delta < 120) {
    return 'about a minute ago';
  } else if(delta < (60*60)) {
    return (parseInt(delta / 60)).toString() + ' minutes ago';
  } else if(delta < (120*60)) {
    return 'about an hour ago';
  } else if(delta < (24*60*60)) {
    return 'about ' + (parseInt(delta / 3600)).toString() + ' hours ago';
  } else if(delta < (48*60*60)) {
    return '1 day ago';
  } else {
    return (parseInt(delta / 86400)).toString() + ' days ago';
  }
}	