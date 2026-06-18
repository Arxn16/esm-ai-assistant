# encoding: UTF-8
require 'resque/errors'
module RetriedJob
  def on_failure_retry(e, *args)
    puts "Performing #{self} caused an exception (#{e}). Retrying..."
    $stdout.flush
    Resque.enqueue self, *args
  end
end

class Task
# encoding: UTF-8
  # extend RetriedJob

  attr_reader :params
  @queue = :task

  def initialize(params)
    @params = params
  end

  def self.perform(params)

   # puts "#{Time.now} : perform with #{params}"
   # dispatch_command
   
  end
    
  def self.enqueue(params)
     queue = 'default'
     queue = params[:queue] if params[:queue]
	   Resque::Job.create(queue.to_sym, self, params)
  end
  
end
