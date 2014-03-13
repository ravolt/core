# Copyright 2014, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class Snapshot < ActiveRecord::Base

  ARCHIVED = -1
  PROPOSED = 0
  COMMITTED = 1
  ACTIVE = 2
  ERROR = 3
  STATES = {
    ARCHIVED => "archived",
    PROPOSED => "proposed",
    COMMITTED => "committed",
    ACTIVE => "active",
    ERROR => "error"
  }

  after_commit :run_if_any_runnable, on: [:create, :update]
  
  belongs_to      :deployment

  has_many        :deployment_roles,  :dependent => :destroy
  has_many        :roles,             :through => :deployment_roles
  has_many        :attribs,           :through => :roles

  has_many        :node_roles,        :dependent => :destroy
  has_many        :nodes,             :through => :node_roles
 
  has_one         :snapshot
  alias_attribute :next,              :snapshot

  def self.state_name(s)
    raise("#{state || 'nil'} is not a valid Snapshot state!") unless s and STATES.include? s
    I18n.t(STATES[s], :scope=>'node_role.state')
  end

  def state_name(s)
    self.class.state_name(s)
  end

  def active?
    committed? &&
      node_roles.committed.not_in_state(NodeRole::ACTIVE).count == 0
  end

  def committed?
    read_attribute('state') == COMMITTED
  end
  
  def proposed?
    read_attribute('state') == PROPOSED
  end

  def archived?
    read_attribute('state') == ARCHIVED
  end

  def annealable?
    committed? && !active? && !error?
  end

  def proposable?
    active? && !deployment.system?
  end

  def error?
    committed? &&
      node_roles.committed.in_state(NodeRole::ERROR).count > 0
  end

  def archive
    write_attribute("state",ARCHIVED)
    save!
  end

  def state
    s = read_attribute("state")
    
    return s if s == ARCHIVED || s == PROPOSED
    return ACTIVE if active?
    return ERROR if error?
    COMMITTED
  end

  def tail?
    snapshot_id.nil?
  end

  def parent
    Snapshot.where(:snapshot_id => id).first
  end

  class MissingJig < Exception
    def initalize(nr)
      @errstr = "NodeRole #{nr.name}: Missing jig #{nr.jig_name}"
    end

    def to_s
      @errstr
    end
    def to_str
      to_s
    end
  end

  # returns a hash with all the snapshot error status information 
  def status
    node_roles.each { |nr| s[nr.id] = nr.status if nr.error?  }
  end

  def commit
    Snapshot.transaction do
      node_roles.in_state(NodeRole::PROPOSED).each { |nr| nr.commit! }
      if proposed?
        write_attribute("state",COMMITTED)
        save!
      end
    end
    Run.run!
    self
  end

  # create a new proposal from the this one
  def propose(name=nil)
    Snapshot.transaction do
      node_roles.each do |nr| nr.propose! end
      write_attribute("state",PROPOSED)
      save!
    end
    self
  end

  def recallable?
    !deployment.system?
  end

  # attempt to stop a proposal that's in transistion.
  # Do this by changing its state from COMMITTED to PROPOSED.
  def recall
    Snapshot.transaction do
      raise "Cannot recall a system deployment" unless recallable?
      write_attribute("state",PROPOSED)
      save!
    end
  end

  private

  def run_if_any_runnable
    Rails.logger.debug("Snapshot: after_commit hook called")
    if node_roles.runnable.count > 0
      Rails.logger.info("Snapshot: #{name} is committed, kicking the annealer.")
      Run.run!
    end
  end
  
end
