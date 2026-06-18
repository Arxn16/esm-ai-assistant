// This is a manifest file that'll be compiled into including all the files listed below.
// Add new JavaScript/Coffee code in separate files in this directory and they'll automatically
// be included in the compiled file accessible from http://example.com/assets/application.js
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// the compiled file.
//
//# require jquery
//= require jquery.min.js
//= require jquery-migrate.js
//= require jquery_ujs
//= require jquery-ui.js
//# require ace.js
//# require mode-html.js
//# require theme-clouds.js
//= require sketch.js
//= require highslide.min.js
//= require elrte.min.js
//= require elfinder.min.js
//= require dragdrop.js
//= require jquery.debouncedresize.min.js
//= require jquery.actual.min.js
//= require jquery.cookie.min.js
//= require bootstrap.min.js
//= require jquery.qtip.min.js
//= require ios-orientationchange-fix.js
//= require antiscroll.min.js
//= require jquery-mousewheel.js
//= require gebo_common.js
//= require sticky.min.js
//= require kendo.all.min.js
//= require jquery.validate.js
//= require gebo_validation.js
//= require tree_helper.js
//# require_tree .



function popitup(url,name,params) {
	newwindow=window.open(url,name,params);
	if (window.focus) {newwindow.focus()}
	return false;
}
hs.graphicsDir = '/highslide/graphics/';

function refresh(){
refresh_remote();
}


function getURLParameter(name,url) {
  return decodeURIComponent((new RegExp('[?|&]' + name + '=' + '([^&;]+?)(&|#|;|$)').exec(url)||[,""])[1].replace(/\+/g, '%20'))||null
}

function refresh_remote(){


   $('a[data-remote],input[data-remote],form[data-remote]').each(function() {
    
	$(this).unbind();
	$(this).bind('ajax:success', function(evt, data, status, xhr){
	obj = $(this);
	url = ''
	if(obj.is('a')){
		url = obj.attr('href')
	}else if(obj.is('form')){
		url = obj.attr('action')
	}
	
	 update = getURLParameter('update',url);
	 try{
	 if(update){
	  target = $("#"+update);
	  target.html(data);
	  }else{
	  $(document).append(data);
      	  }
	}catch(err)
	{
	alert(err)
	}

	refresh_remote();
      });
	
   });
	
}

hs.numberOfImagesToPreload = 10000;

$( document ).ready(function() {
   

  
	// alert('ok')
	if(console){
		
		fixed=false;
		jQuery('.mainwrapperheader').removeClass('fixed_header');
		jQuery('.mainwrapperinner').removeClass('fixed_body');	
		
	}
  // kendo.support.touch = true;
    $(window).scroll(function(){



	try{
	console.refresh('')
			
	}catch(e){
	// alert(e);
	
}

});
 

});

// $( document ).ready(function() {

var esm_helper = new function(){
	
	this.register = {};
	
	this.get = function(id){
		console.log("esm_helper get for "+id)
		
		return this.register[id];
	};
	this.push = function(id,obj){
		
		console.log("esm_helper push for "+id)
		this.register[id] = obj;
	};
	this.count = function(){
		alert('Size of register = '+this.register.length);
	};
	
}

console.log("esm_helper defined ")


// esm_helper.count()

// esm_helper.push('soup',{'name':'Soup'})


// esm_helper.count()

// alert(esm_helper.get('soup')['name'])


// });













