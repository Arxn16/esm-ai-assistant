class Log < ActiveRecord::Base
  attr_accessible :user_id,:role_id,:remote_ip,:action,:path,:remark,:esm_id
end
