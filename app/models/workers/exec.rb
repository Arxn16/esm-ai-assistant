

class CMDTask < Task
  
  def self.perform(params)
  
      cmd = params['cmd']
      
      # out = `#{cmd}`
      
      eval cmd
      
      
      puts "FINISH"
      
      
  end

end