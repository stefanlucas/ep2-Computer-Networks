require 'socket'
require 'ipaddr'

class Peer
  def initialize(port, number = nil)
    @server = TCPServer.open(port)
    @port = port
    @number = number
    @is_prime = true
    @shutdown = false
    @interval = Hash.new
    @interval_queue = Array.new
    @peers = Hash.new
    @id = nil

    Socket.ip_address_list.each do |addr_info|
      if (addr_info.ip_address =~ /192.168.1.*/) == 0
        @id = addr_info.ip_address
      end 
    end
    puts @id
    if @id == nil
      puts "Erro, deveria existir uma interface lan com ip 192.168.1.*"
      exit(1)
    end

    if number != nil
      @leader = true
      @interval = {low: 2, high: Math.sqrt(number).to_i}
    else 
      @leader = false
      connect_leader
    end

    run
  end

  def run
    primality_test
    while not @shutdown
      handle(@server.accept)
    end
  end

  def handle(socket)

  end

  def primality_test
    Thread.new do
      while true
        for i in @interval[:low]..@interval[:high]
          puts "testando " + i.to_s
          if @number % i == 0
            @is_prime = false
            puts "O número não é primo"
            exit(0)
          end 
        end
        puts "Nenhum número do intervalo [" + low.to_s + ", " + high.to_s + "] divide " + @number.to_s
        break
      end
    end
  end

  def connect_leader
    ips = ipscan()
    ips.each do |ip|
      begin
      socket = TCPSocket.open(ip, @port)
      socket.close
      rescue
        next
      end
    end
    puts "End connections"
  end

  def leader_election
  end

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
end

if ARGV[0] == nil 
  Peer.new(2000)
else 
  Peer.new(2000, ARGV[0].to_i)
end