require 'ipaddr'
def ipscan
  ips = IPAddr.new("192.168.1.0/24").to_range
  ip_array = []
  threads = ips.map do |ip|
    Thread.new do
      status = system("ping -q -W 1 -c 1 #{ip}",
                    [:err, :out] => "/dev/null")
    ip_array << ip.to_s if status
    end
  end
  threads.each {|t| t.join}
  return ip_array
end