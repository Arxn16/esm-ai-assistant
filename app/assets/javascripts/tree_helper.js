
vlocal = null;
   function ESMTree(record_id, model, ap, fmap, master){
  
    this.record_id = record_id;
	this.map = map;
	this.fmap = fmap;
	this.master = master;

    this.vlocal = null
    this.report_monitor = []
    this.report_reg = {}
    this.report_type = {}
    this.report_tmp = {}
  
	this.current_active; 
	this.model = model;
	// console.log('sodfjid  ' +this.model);
   
	// alert(this.record_id)
	

   
   	
	this.changeValue = function(ofid,t,value,text) {
	
	
		// console.log("call changeValue "+ofid+' '+t+ ' ' +value+' '+text)
		t = ofid.split('-')
		prefix=''
		fid=ofid
		if(t.length>1){
			fid = t[t.length-1]
			prefix= t.slice(0,-1).join('-')+'-'
		}
		
		obj = this.map[fid]
		
		// console.log(this.fmap)
		
		if(true){
		tmp = value.split("|")
		
		// console.log(obj)
		for(var idx in obj['items']){
			i = obj['items'][idx]
			// console.log("test "+i['text'] + " "+ tmp.indexOf(i['id']))
			
			if(tmp.indexOf(i['id'])>=0||value=='TRUE'||value=='true'){
				// console.log("select "+i['text'])
				
				id = i['id']
				if(id[0]=='F'){
					id = this.fmap[id]
					// console.log('found '+id)
				
					$('#'+prefix+id).show();
				}
				
				if(i['items']){
					
					for(var jdx in i['items']){
						j = i['items'][jdx]
						id = this.fmap[j['id']]
						// console.log('found 2 '+id)
						if(id[0]=='F'){
							id = "data-"+id
						}
						// console.log('found 2 '+prefix+id)
						
						$('#'+prefix+id).show();
					}
					
					
				}
				
			}else{
				
				id = i['id']
				if(id[0]=='F'){
					id = this.fmap[id]
					$('#'+prefix+id).hide();
				}
				
				if(i['items']){
					for(var jdx in i['items']){
						j = i['items'][jdx]
						id = this.fmap[j['id']]
						if(id[0]=='F'){
							id = "data-"+id
						}
						$('#'+prefix+id).hide();
					}
				}
			}
			
		}
		
		}else{
			// console.log("Null")
		}
		
	}



    this.regField = function(field_name,div_id,tmp,type){

        this.report_reg[field_name] = div_id
        this.report_type[field_name] = type

        if (typeof(tmp) != "undefined"){
            this.report_tmp[field_name] = tmp
        }

    }
    
   this.initReport = function(){
	   console.log("call init Report")
	    var local_obj = this
	
	    $(".report-field").each(function(index){
            var id = $(this).attr('id')
            var name = $(this).attr('name')
            var tmp = $(this).attr('template')
            var type = $(this).attr('type')
            
            
            local_obj.regField(name,id,tmp,type)
            
        });
        
        this.vlocal = this.master[this.model]
		 console.log("call init Report")
	   console.log(this.model);
	
	
	
   }
   this.regMonitor = function(func){
	 // if(this.report_monitor.length==0)
	 // console.log(fun)
	 this.report_monitor.push(func);
	 // this.report_monitor =  jQuery.unique(this.report_monitor);
	
	}
	
	this.sizeMonitor = function(){
		console.log("monitor "+this.report_monitor.length)
	}
	
    this.get_value = function(name){
	o = $('#data-'+name)
        if(o.attr("type")=='checkbox'){
	  if(o.attr('checked'))
	 	return 'true'
	  else
	        return 'false'
	}else return o.val()
	
    }


   this.updateReport = function(){
   
   // console.log(this.vlocal);
    this.sizeMonitor();

	for (var key in this.report_reg) {

        if (this.report_reg.hasOwnProperty(key)) {

            // console.log("update Report...." + key)
            id = this.report_reg[key]

            value = $("#data-"+key).val()
			if(value){
            values = value.split("|")

            values_text = []
            for(var vi in values){
                v = values[vi]
                if(typeof this.vlocal[key] != 'undefined'){
                v = this.vlocal[key][v]
                values_text.push(v)}
            }

            label = key
            template = 'default'
            if (typeof(this.report_tmp[key]) != "undefined"){
                template = this.report_tmp[key];
            }
			vlocal = this.vlocal;
			object = this;
            var template = kendo.template($("#"+template).html());
            var result = template(label,value,values,values_text,vlocal,object); 
            $("#"+id).html(result)
			}
        }


    }

        for(var m in this.report_monitor){
            fm = this.report_monitor[m]
            fm.apply();
        }
	
		// console.log("call update Report")
	
	
    }


}
    