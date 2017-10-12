require 'socket'
require 'ipaddr'

Thread.abort_on_exception=true
r_interval_mutex = Mutex.new
$quantum = 100000

class Peer
  def initialize(port, number = nil)
    @server = TCPServer.open(port)
    @port = port
    @number = number
    @shutdown = false
    @interval = Hash.new
    @interval_queue = Array.new
    @remaining_interval = Hash.new
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
      @remaining_interval = @interval = {low: 2, high: number.abs-1}
    else 
      @leader = false
      connect_peers
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
    Thread.new {
      message = socket.gets
      puts "Peer " + socket.peeraddr[3] + " request: " + message
      message.split!(/[ \r\n]/)
      if @peers[socket.peeraddr[3]] == nil
        @peers[socket.peeraddr[3]] = Hash.new
      end
      if @leader
        case message[0]
        when "leader?"
          socket.puts "yes"
        when "get_computation_info"
        when "new_interval"
          r_interval_mutex.synchronize {
            has_interval = true
            if remaining_interval[:low] >= remaining_interval[:high]
              if @interval_queue.empty?
                has_interval = false
                @peers[socket.peeraddr[3]][:low] = @peers[socket.peeraddr[3]][:high] = nil
                socket.puts "no_interval"
              else
                low, high = @interval_queue.shift                  
              end
            else 
              low = @remaining_interval[:low]
              if @remaining_interval[:low] + quantum + 1 > @remaining_interval[:high]
                high = @remaining_interval[:high]
                @remaining_interval[:low] = @remaining_interval[:high]
              else
                high = low + quantum
                @remaining_interval[:low] += (quantum + 1) 
              end
            end
            if has_interval
              socket.puts low.to_s + "," + high.to_s
              @peers[socket.peeraddr[3]][:low] = low
              @peers[socket.peeraddr[3]][:high] = high
            end                        
          }
        else
          socket.puts "Could not resolve message"
        end
      else
        case message[0] 
        when "peer_info"
          socket.puts @interval[:low] + "," + @interval[:high]
        when "leader?"
          socket.puts "no"
        when "ping"
          socket.puts "pong"
        when "finish_interval_computation"
          socket.puts "ok"
        when "not_prime"
          socket.puts "ok"
          puts "Number is not prime " + message[1] + " divides " + @number.to_s
          exit(0) 
        else
          socket.puts "Could not resolve message"
        end
      end
      socket.close
    }
  end

  def primality_test
    tr = Thread.new {
      if @number.abs == 1 or @number.abs == 0
        puts "Não é primo"
        Thread.exit 
      end
      for i in @interval[:low]..@interval[:high]
        if @number % i == 0
          puts "Não é primo"
          Thread.exit
        end
      end
      puts "eh primo"
    }
  end

  def connect_peers
    while @leader_id == nil
    ips = ipscan()
    ips.each do |ip|
      begin
        next if @id == ip
        puts "Connected to peer from " + ip
        socket = TCPSocket.open(ip, @port)          
        socket.puts "leader?"
        response = socket.gets
        puts "Received response " + response.chomp 
        response.split!(/[ \r\n]/)
        if response[0] == "yes"
          puts "Peer with ip " + ip + " is the leader"
          @leader_id = ip
          socket = TCPSocket.open(ip, @port)
          socket.puts "get_computation_info"
          response = socket.gets
          puts "Received response " + response.chomp
          response.split!(/[ \r\n]/)
          @number = response[0].to_i
          x, y = response[1].split(",")
          @remaining_interval[:low], @remaining_interval[:high] = x.to_i, y.to_i
          for i in 2..(response.size - 1) 
            low, high = response[i].split(",")
            @interval_queue << {low: low.to_i, high: high.to_i}
          end
          socket = TCPSocket.open(ip, @port)
          socket.puts "new_interval"
          response = socket.gets.chomp.split([/, \r\n/])
          @interval[:low] = response[0].to_i
          @interval[:high] = response[1].to_i
        end
        @peers[ip] = Hash.new
        socket = TCPSocket.open(ip, @port)
        socket.puts "peer_info"
        response = socket.gets.chomp.split([/, \r\n/]) 
        @peers[ip][:low] = response[0].to_i
        @peers[ip][:high] = response[1].to_i        
      rescue
        next
      end
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