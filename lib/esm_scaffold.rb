

def esm_scaffold model, &block
  
  # GET /records
  # GET /records.xml
  model = model.to_s
  classname = eval model.camelize
  pathname = model.pluralize

  before_filter :setup
  columns = classname.column_names
  columns.delete 'id'
  columns.delete 'created_at'
  columns.delete 'updated_at'
  # columns += %w{Show Edit Delete}
  config = {:columns=>columns,:fields=>{},:list=>{:columns=>{},:actions=>{}},:new=>{:columns=>{},:actions=>{}},:edit=>{:columns=>{},:actions=>{}},:show=>{:columns=>{},:actions=>{}}}

  
  yield config if block
  
  define_method :setup do
    @classname = classname
    @pathname = '/'+pathname
    @config = config
  end
  
  define_method :index do
   
    @config[:columns]=@config[:list][:columns] if @config[:list][:columns].size>0
    
    records = []
    @count = classname.count
    
    key = params[:q]
    if key
       key.upcase!
       records = classname.all.to_a
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
    records = classname.all.to_a.collect{|i| i if i.updated_at and i.updated_at.strftime("%d%m%Y")==t}.compact!
    elsif !params[:start] and !params[:limit]
    records = classname.all.to_a
    else
    records = classname.where(:offset=>params[:start].to_i, :limit=>params[:limit].to_i).all().to_a
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

  # GET /records/1
  # GET /records/1.xml
  define_method :show do
    @config[:columns]=@config[:show][:columns] if @config[:show][:columns].size>0
    @record = classname.find(params[:id])
    respond_to do |format|
      format.html { render :template => 'esm/scaffold/show'}
      format.xml  { render :xml => @record }
    end
  end

  # GET /records/new
  # GET /records/new.xml
  define_method :new do
    @record = classname.new
       @config[:columns]=@config[:new][:columns] if @config[:new][:columns].size>0
    respond_to do |format|
      format.html { render :template => 'esm/scaffold/new'}
      format.xml  { render :xml => @record }
    end
  end

  # GET /records/1/edit
  define_method :edit do
     @config[:columns]=@config[:edit][:columns] if @config[:edit][:columns].size>0
    @record = classname.find(params[:id])
    render :template => 'esm/scaffold/edit'
  end

  # POST /records
  # POST /records.xml
  define_method :create do
    @record = classname.new(params[model])
       @config[:columns]=@config[:new][:columns] if @config[:new][:columns].size>0
    respond_to do |format|
      if @record.save
        format.html { redirect_to(@record, :notice => 'record was successfully created.') }
        format.xml  { render :xml => @record, :status => :created, :location => @record }
      else
        format.html { render :template =>  'esm/scaffold/new' }
        format.xml  { render :xml => @record.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /records/1
  # PUT /records/1.xml
  define_method :update do
    @record = classname.find(params[:id])
       @config[:columns]=@config[:edit][:columns] if @config[:edit][:columns].size>0
    respond_to do |format|
      if @record.update_attributes(params[model])
        format.html { redirect_to(@record, :notice => 'record was successfully updated.') }
        format.xml  { head :ok }
      else
        format.html { render :template => 'esm/scaffold/edit' }
        format.xml  { render :xml => @record.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /records/1
  # DELETE /records/1.xml
  define_method :destroy do
    if params[:id]!='0'
    @record = classname.find(params[:id])
    @record.destroy
   else
     classname.delete_all
    end

    respond_to do |format|
      format.html { redirect_to(@pathname) }
      format.xml  { head :ok }
    end
  end

  
  

  
  
end
