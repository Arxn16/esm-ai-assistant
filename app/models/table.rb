class Table < ActiveRecord::Base
  self.table_name =  :esm_tables
  attr_accessible :esm_id,:schema_id,:name,:data, :command
  belongs_to :schema
  
  def data_columns
    list = {}
    if self.data
      self.data.lines.each do |i|
        l = i.split(',')
        if l[0].index('key')
          list[l[0].split[-1][1..-1]]=l[-1].strip
        end
      end
    end
    return list
  end
  
  
  def add_column name, data_type
     unless data_columns[name]
     self.data = '' unless self.data
     self.data += "\n\tkey :#{name}, #{data_type}\n"
     self.save
     end
     
  end
  
end
