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

class NetworkAllocation < ActiveRecord::Base

  validate :sanity_check_address
  
  belongs_to :network_range
  belongs_to :network
  belongs_to :node

  alias_attribute :range,       :network_range

  scope  :node,     ->(n)  { where(:node_id => n.id) }
  scope  :network,  ->(net){ joins(:network_range).where('network_ranges.network_id' => net.id) }

  def address
    IP.coerce(read_attribute("address"))
  end

  def address=(addr)
    write_attribute("address",IP.coerce(addr).to_s)
  end

  # rough way to guess port mappings
  def guess_interface(nics)

    # parse conduit
    unless network_range.conduit =~ /^([-+?]*)(\d{1,3}[mg])(\d+)$/
      return nil
    end
    direction = $1
    speed = $2
    pos = $3
    speed_pos = Network::CONDUIT_SPEEDS.find_index speed
    # narrow choices to match conduit
    seeking = case direction
        when "+" then Network::CONDUIT_SPEEDS[speed_pos+1..100]
        when "-" then Network::CONDUIT_SPEEDS[0..speed_pos-1]
        when "?" then Network::CONDUIT_SPEEDS[speed_pos..100]
        else Network::CONDUIT_SPEEDS[speed_pos]
    end
    # find matching interfaces (assume ordering)
    nic = nics.keys[pos.to_i] rescue nil
    if nic.nil?
      return I18n.t('network_allocation.guess.no_nic')
    elsif nics[nic]['speeds'].include? speed
      return nic
    else
      return I18n.t('network_allocation.guess.no_speed')
    end

  end

  private

  def sanity_check_address
    unless network_range === address
      errors.add("Allocation #{network.name}.#{network_range.name}.{address.to_s} not in parent range!")
    end
  end
  
end
