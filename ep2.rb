require 'socket'
require 'ipaddr'
require 'json'

Thread.abort_on_exception=true

class Peer
  def initialize(port, number = nil)
    @server = TCPServer.open(port)
    @port = port
    @number = number
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
    if @id == nil
      puts "Erro, deveria existir uma interface lan com ip 192.168.1.*"
      exit(1)
    end
    if number != nil
      @leader = true
      @interval = {low: 2, high: number.abs}
    else 
      @leader = false
      connect_peers
    end

    run
  end

  def run
    #primality_test
    while not @shutdown
      handle(@server.accept) 
    end
  end

  def handle(socket)
    Thread.new {
      puts "Peer " + socket.peeraddr[3] + " mandou uma mensagem"
      message = socket.gets.split(" \n\r")
      puts "mensagem = " + message[0]
      if @leader
        case message[0]
        when "request_peer_info"
          socket.puts "leader=true"
        else
          puts "Num intindi o q ele falo"
          socket.puts "Num intindi o q ce falo"
        end
      else # tratar mensagens de um peer normal
        
      end
    }
  end

  def primality_test
    Thread.new {
      if @number.abs == 1 or @number.abs == 0
        puts "Não é primo"
      end
      for i in @interval[:low]..@interval[:high]
        puts i
        if @number % i == 0
          puts "Não é primo"
        end
      end
      puts "eh primo"
    }
  end

  def connect_peers
    ips = ipscan()
    ips.each do |ip|
      begin
        next if @id == ip
        socket = TCPSocket.open(ip, @port)
        puts "Connected to peer from " + socket.peeraddr[3]          
        socket.puts "request_peer_info"
        puts "Received request_peer_info response from " + socket.peeraddr[3]
        response = socket.gets.split(/[ \r\n]/)
        if response[0] == "leader:true"
          puts "Peer with " + ip + "is the leader"
          @leader_id = ip
        end
        @peers[socket.peeraddr[3]] = Hash.new
        @peers[socket.peeraddr[3]]         
        socket.close
      rescue
        next
      end
    end
    puts "End finding connections"
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