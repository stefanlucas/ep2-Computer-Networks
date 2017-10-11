require 'socket'

Socket.ip_address_list.each do |addr_info|
  if (addr_info.ip_address =~ /192.168.*.*/) == 0
   puts addr_info.ip_address
  end
end
