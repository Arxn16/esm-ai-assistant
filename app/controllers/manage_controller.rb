class ManageController < EsmAdminController
 
 before_filter :model_filter
 layout 'esm_application'
 
 def model_filter
        
        
        @model_name =  params[:model].singularize
        
        @model = eval @model_name.camelize
        
        @classname = @model
        @pathname = "/manage/#{params[:model]}" 
        
        columns = @model.column_names
        columns.delete 'id'
        columns.delete 'created_at'
        columns.delete 'updated_at'
             # columns += %w{Show Edit Delete}
        config = {:columns=>columns,:fields=>{},:list=>{:columns=>{},:actions=>{}},:new=>{:columns=>{},:actions=>{}},:edit=>{:columns=>{},:actions=>{}},:show=>{:columns=>{},:actions=>{}}}

        @config=config
        
 end
 
 def index
         @config[:columns]=@config[:list][:columns] if @config[:list][:columns].size>0

             records = []
             @count = @model.count

             key = params[:q]
             if key
                key.upcase!
                records = @model.all
                records.collect! do |i|
                    found = false 
                    for j in @config[:columns]
                      if i[j].to_s==key or i[j].to_s.upcase.index(key)
                        found = true
                        break;
                      end
                    end
                    if found 
                       i
                    else
                       nil
                    end
                  end
             records.compact!
             elsif params[:today]
             t = Time.now.strftime("%d%m%Y")
             records = @model.all.collect{|i| i if i.updated_at and i.updated_at.strftime("%d%m%Y")==t}.compact!
             elsif !params[:start] and !params[:limit]
             records = @model.all :offset=>0, :limit=>50
             else
             records = @model.all :offset=>params[:start].to_i, :limit=>params[:limit].to_i
             end

             sort = params[:sort]
             if sort
             records.sort!{|a,b| a[sort]<=>b[sort]} 
             records.reverse! if params[:dir] and params[:dir]=='DESC'
             end

             @records = records
             respond_to do |format|
               format.json { render :template =>'esm/scaffold/index'}
               format.html { render :template => 'esm/scaffold/index'}
               format.xml  { render :xml => @records }
             end
      
 end
 
 def show
         @config[:columns]=@config[:show][:columns] if @config[:show][:columns].size>0
         @record = @model.find(params[:id])
         respond_to do |format|
           format.html { render :template => 'esm/scaffold/show'}
           format.xml  { render :xml => @record }
         end   
 end
 
 def new
         @record = @model.new
          @config[:columns]=@config[:new][:columns] if @config[:new][:columns].size>0
          respond_to do |format|
            format.html { render :template => 'esm/scaffold/new'}
            format.xml  { render :xml => @record }
          end
 end
 
 def edit
         @config[:columns]=@config[:edit][:columns] if @config[:edit][:columns].size>0
         @record = @model.find(params[:id])
         render :template => 'esm/scaffold/edit'
 end
 
 def create
         @record = @model.new(params[@model_name])
            @config[:columns]=@config[:new][:columns] if @config[:new][:columns].size>0
         respond_to do |format|
           if @record.save
             format.html { redirect_to("#{@pathname}/#{@record.id}", :notice => 'record was successfully created.') }
             format.xml  { render :xml => @record, :status => :created, :location => @record }
           else
             format.html { render :template =>  'esm/scaffold/new' }
             format.xml  { render :xml => @record.errors, :status => :unprocessable_entity }
           end
         end   
 end
 
 def update
         @record = @model.find(params[:id])
            @config[:columns]=@config[:edit][:columns] if @config[:edit][:columns].size>0
            
         respond_to do |format|
           if @record.update_attributes(params[@model_name])
             format.html { redirect_to(@pathname+"/#{@record.id}", :notice => 'record was successfully updated.') }
             format.xml  { head :ok }
           else
             format.html { render :template => 'esm/scaffold/edit' }
             format.xml  { render :xml => @record.errors, :status => :unprocessable_entity }
           end
         end
 end
 
 def destroy
          if params[:id]!='0'
          @record = @model.find(params[:id])
          @record.destroy
         else
           @model.delete_all
          end

          respond_to do |format|
            format.html { redirect_to(@pathname) }
            format.xml  { head :ok }
          end 
 end
 
end
