require 'socket'
require 'ipaddr'
require 'thread'
require 'time'

Thread.abort_on_exception=true #tirar isso depois
class Peer
  def initialize(port, number = nil, quantum=10000000)
    @server = TCPServer.open(port)
    @port = port
    @number = number
    @prime = false
    @interval = Hash.new
    @interval_queue = Array.new
    @remaining_interval = Hash.new
    @peers = Hash.new
    @id = nil
    @leader = false
    @leader_id = nil
    @quantum = quantum
    @t = Time.new
    @t0 = Time.new
    @filename = "log.txt"
    @peers_mutex = Mutex.new

    File.open(@filename, 'w') { |f| 
      f.flock(File::LOCK_EX)
    }

    Socket.ip_address_list.each do |addr_info|
      if (addr_info.ip_address =~ /192.168.*.*/) == 0
        @id = addr_info.ip_address
        digits = addr_info.ip_address.split(".")
        @ip_digit = digits[2]
      end 
    end
    if @id == nil
      puts "Erro, deveria existir uma interface lan com ip do tipo 192.168.*.*"
      exit(1)
    end
    if number != nil
      @leader = true
      @leader_id = @id
        if number.abs == 2 
          puts "Is prime"
          exit(0)
        elsif number.abs == 1 || number.abs == 0
          puts "Not prime"
          exit(0)
        end 

        if @quantum > (number.abs - 1)
          high = number.abs - 1
        else
          high = @quantum
        end

        @interval = {low: 2, high: high}
        @remaining_interval = {low: high + 1, high: number.abs - 1}
      else 
      @leader = false
      connect_peers
    end

    run
  end

  def run
    primality_test
    heartbeat
    loop {
      handle(@server.accept) 
    }
  end

  def write_log(line) 
    File.open(@filename, 'a') { |f| 
      f.flock(File::LOCK_EX)
      f.puts line + " timestamp: " + Time.new.to_s
    }
  end

  def handle(socket)
    Thread.new { 
      #begin
      message = socket.gets
      # caso em que é a primeira vez que o peer se conecta
      if @peers[socket.peeraddr[3]] == nil
        write_log "Peer " + socket.peeraddr[3] + " connected"  
        puts socket.peeraddr[3] + " connected"
        @peers_mutex.synchronize {
          @peers[socket.peeraddr[3]] = Hash.new
        }
        @peers[socket.peeraddr[3]][:status] = "connected"
      # caso a conexão do peer tenha caido anteriormente
      elsif @peers[socket.peeraddr[3]][:status] == "disconnected"        
        write_log "Peer " + socket.peeraddr[3] + " reconnected" 
        puts socket.peeraddr[3] + "reconnected to the network"
        @peers[socket.peeraddr[3]][:status] = "connected"
      end
      write_log "Peer " + socket.peeraddr[3].to_s + " request: " + message.chomp 
      #puts "Peer " + socket.peeraddr[3].to_s + " request: " + message.chomp
      message = message.split(/[ \r\n]/)
      case message[0]
        when "leader?"
          if @leader
            response = "yes"
          else
            response = "no"
          end
        when "leader_election"
          write_log "Peer " + socket.peeraddr[3] + " initiated the election" 
          response = socket.gets.split(/[ \r\n]/)
          if response[0] == "you_were_elected"
            write_log "Election result: I was elected as the leader"
            @leader = true
            @leader_id = @id
            x, y = response[1].split(",")
            @remaining_interval[:low], @remaining_interval[:high] = x.to_i, y.to_i
            @interval_queue = []
            if response.length > 2 
              for i in 2..(response.length - 1) 
                low, high = response[i].split(",")
                @interval_queue << {low: low.to_i, high: high.to_i}
              end
            end
          else
            @leader = false
            @leader_id = response[1]
            write_log "Election result: Leader is " + @leader_id
          end
          @t = Time.now
        when "get_computation_info"
          response = @number.to_s + " " + @quantum.to_s + " " + @t0.to_s + " " + @remaining_interval[:low].to_s + "," + @remaining_interval[:high].to_s
          @interval_queue.each do |interval|
            response += " " + interval[:low].to_s + "," + interval[:high].to_s
          end
        when "new_interval"
          #se o peer realmente terminou o trabalho ou é a primeira vez que ele se conecta
          if @peers[socket.peeraddr[3]][:low] == false || @peers[socket.peeraddr[3]][:low] == nil    
              @peers[socket.peeraddr[3]][:low], @peers[socket.peeraddr[3]][:high] = select_interval() 
              if @peers[socket.peeraddr[3]][:low] == false
                response = "no_interval"
              else
                response = @peers[socket.peeraddr[3]][:low].to_s + "," + @peers[socket.peeraddr[3]][:high].to_s
              end         
          else 
            #caso o peer tinha se desconectado anteriormente sem terminar o trabalho e não deu tempo do líder perceber
            response = @peers[socket.peeraddr[3]][:low].to_s + "," + @peers[socket.peeraddr[3]][:high].to_s
          end 
        when "peer_interval"
          if @interval[:low] == false || @interval[:low] == nil
            response = "no_interval"
          else
            response = @interval[:low].to_s + "," + @interval[:high].to_s
          end
        when "ping"
          response = "pong"
        when "finish_interval_computation"
          @peers[socket.peeraddr[3]][:low] = @peers[socket.peeraddr[3]][:high] = false
          response = "ok"
        when "is_prime"
          tf = Time.new - @t0
          puts "\n" + @number.to_s + " is prime" + "\ntime: " + tf.to_s + " s"
          write_log "Peer " + socket.peeraddr[3] + " sent: " + @number.to_s + " is prime"
          socket.puts "ok"
          exit(0)
        when "not_prime"
          tf = Time.new - @t0
          puts "\nNumber is not prime " + message[1] + " divides " + @number.to_s + "\ntime: " + tf.to_s + " s"
          write_log "Peer " + socket.peeraddr[3] + " sent: number is not prime " + message[1] + " divides " + @number.to_s
          socket.puts "ok"
          exit(0) 
        else
          response = "Unknow command"
        end
        #puts "response: " + response.to_s
        write_log "response: " + response.to_s
        socket.puts response
      socket.close
      #rescue
      #end
    }
  end

  def select_interval
    if @remaining_interval[:low] >= @remaining_interval[:high]
      if @interval_queue.empty?
        return [false, false]
      end
      interval = @interval_queue.shift
      return [interval[:low], interval[:high]]
    end
    low = @remaining_interval[:low]
    if @remaining_interval[:low] + @quantum + 1 > @remaining_interval[:high]
      high = @remaining_interval[:high]
      @remaining_interval[:low] = @remaining_interval[:high]
    else
      high = low + @quantum
      @remaining_interval[:low] += (@quantum + 1) 
    end

    return [low, high]
  end


  def primality_test
    tr = Thread.new {
      time_heartbeat = Time.new
      loop {
        if @interval[:low] == false || @interval[:low] == nil || @interval[:low] == 0
          write_log "waiting for new interval or end of primality test"
          puts "waiting for new interval or end of primality test"
        else
          write_log "testing interval " + @interval[:low].to_s + "," + @interval[:high].to_s
          puts "testing interval " + @interval[:low].to_s + "," + @interval[:high].to_s
        end
        if @interval[:low] != false and @interval[:low] != nil and @interval[:low] != 0
          i = @interval[:low]
          while i <= @interval[:high] do
            if @number % i == 0
              write_log "Broadcasting: not prime " + i.to_s + " divide " + @number.to_s 
              tf = Time.new - @t0
              puts "\nNot prime " + i.to_s + " divide " + @number.to_s + "\ntime: " + tf.to_s + " s"
              message = "not_prime" + " " + i.to_s
              broadcast(message)
              exit(0)
            end
            i += 1
          end
          message = "finish_interval_computation " + @interval[:low].to_s + "," + @interval[:high].to_s
          #write_log "Broadcasting: " + message
          broadcast(message)
        end
        if Time.new - time_heartbeat > 15
          heartbeat
          time_heartbeat = Time.new
        end
        if @leader
          if check_end() == true
            write_log  "Broadcasting: " + @number.to_s + " is prime"
            tf = Time.now - @t0
            puts "\nThe number is prime\ntime: " + tf.to_s + " s"
            broadcast("is_prime")
            exit(0)
          end 
          @interval[:low], @interval[:high] = select_interval()
          if @interval[:low] == false || @interval[:high] == false
            sleep(0.1)
          end
        else
          conn_failed = false
          begin 
            socket = TCPSocket.open(@leader_id, @port)
            socket.puts "new_interval"
            response = socket.gets.chomp
          rescue
            conn_failed = true
          end
          if conn_failed || response == "no_interval"
            sleep(0.1)
            @interval[:low] = @interval[:high] = false
          else
            response = response.split(",")
            @interval[:low], @interval[:high] = response[0].to_i, response[1].to_i          
          end
        end
        if @leader 
          puts "*"*15 + "LEADER" + "*"*15
        end
        if @leader and Time.now - @t > 10
          write_log "Starting leader election"
          puts "Starting leader election"
          leader_election
          @t = Time.now
        end    
      }
    }
  end

  def leader_election
    array = [[@id, nil]]
    pendent_interval = []
    @peers_mutex.synchronize {
      @peers.each_key do |id|
        begin
          socket = TCPSocket.open(id, @port)
          socket.puts "leader_election"
          array.push([id, socket]) 
        rescue
          @peers[id][:status] = "disconnected"
          if @peers[id][:low] != false and @peers[id][:low] != nil and @peers[id][:high] != 0
            pendent_interval.push({low: @peers[id][:low], high: @peers[id][:high]})
          end
        end
      end
    }
    elected_leader = rand(array.length)
    if array[elected_leader][0] == @id
      @leader = true
      puts "Election finished, I'm the leader"
      write_log "Election finished, I'm the leader"
    else
      @leader = false
      puts "leader_is " + @leader_id
      write_log "leader_is " + @leader_id
    end
    @leader_id = array[elected_leader][0]
    array.each do |x|
      socket = x[1]
      if @id != x[0]
        if @leader_id == x[0]
          response = "you_were_elected " + @remaining_interval[:low].to_s + "," + @remaining_interval[:high].to_s
          @interval_queue.each do |interval|
            response += " " + interval[:low].to_s + "," + interval[:high].to_s
          end
          pendent_interval.each do |interval|
            response += " " + interval[:low].to_s + "," + interval[:high].to_s
          end
          socket.puts response
        else
          socket.puts "leader_is " + @leader_id
        end
      end
    end
  end

  def try_connect(id)
    begin 
      return TCPSocket.open(id, @port)
    rescue
      return false
    end
  end

  def check_end
    if @remaining_interval[:low] >= @remaining_interval[:high] && @interval_queue.empty?
      @peers_mutex.synchronize {
      @peers.each_key do |id| 
        if (@peers[id][:low] != false && @peers[id][:low] != nil && @peers[id][:low] != 0)
          puts "Pending test: " + @peers[id][:low].to_s + ", " + @peers[id][:high].to_s
          socket = try_connect(id)
          if socket != false
            begin
              socket.puts "ping"
              socket.gets
            rescue
              socket = false
            end
          end
          if socket == false
            puts "Peer " + id + " is disconnected, putting on pendent interval queue"
            @interval_queue.push({low: @peers[id][:low], high: @peers[id][:high]})
            @peers[id][:low] = @peers[id][:high] = false
            @peers[id][:status] = "disconnected"
          end
          return @prime = false
        end
      end
      }
      return @prime = true
    end
    return @prime = false
  end

  def heartbeat
    @peers_mutex.synchronize {
      @peers.each_key do |id|
        socket = try_connect(id)
        begin
          socket.puts "ping"
          socket.gets
        rescue
          write_log "Peer " + id + " disconnected"
          puts "Peer " + id + " disconnected"
          @peers[id][:status] = "disconnected"
          next
        end
      end  
    }
  end

  def broadcast(message)
    @peers_mutex.synchronize {
      @peers.each_key do |id|
        begin
          if message == "is_prime" || message == "not_prime"
            puts "sending end message to peer " + id
          end
          socket = TCPSocket.open(id, @port)
          socket.puts message
          socket.gets 
        rescue
          next
        end
      end
    }
  end

  def connect_peers
    ips = ipscan()
    puts "Machine list from this network"
    ips.each do |ip|
      puts "ip = " + ip
    end
    ips = ipscan()
    ips.each do |ip|
      begin
        if ip == @id
          next
        end 
        response = nil
        socket = Socket.tcp(ip, @port, connect_timeout: 1) { |socket|
          puts "Connected to peer from " + ip          
          socket.print "leader?"
          socket.close_write
          response = socket.read
        }
        puts "Received response " + response.chomp 
        response = response.split(/[ \r\n]/)
        if response[0] == "yes"
          puts "Peer with ip " + ip + " is the leader"
          @leader_id = ip
          socket = TCPSocket.open(ip, @port)
          socket.puts "get_computation_info"
          response = socket.gets
          puts "Received response " + response.chomp
          response = response.split(/[ \r\n]/)
          @number = response[0].to_i
          @quantum = response[1].to_i
          dia, hora, gmt = response[2], response[3], response[4]
          @t0 = Time.parse(dia + " " + hora + " " + gmt)
          puts "TEMPO DE INICIO DO BAGUIIIIIIIIIIIIIIIIIIIIIIIIIIIIII: " + @t0.to_s
          x, y = response[3].split(",")
          @remaining_interval[:low], @remaining_interval[:high] = x.to_i, y.to_i
          for i in 4..(response.size - 1) 
            low, high = response[i].split(",")
            @interval_queue << {low: low.to_i, high: high.to_i}
          end
          socket = TCPSocket.open(ip, @port)
          puts "Requesting new interval"
          socket.puts "new_interval"
          response = socket.gets
          puts "Response: " + response
          if response.chomp == "no_interval"
            @interval[:low] = @interval[:high] = false
          else
            response = response.chomp.split(/[,\r\n]/) 
            @interval[:low] = response[0].to_i
            @interval[:high] = response[1].to_i
          end
        end
        @peers[ip] = Hash.new
        @peers[ip][:status] = "connected"
        socket = TCPSocket.open(ip, @port)
        puts "Requesting peer interval"
        socket.puts "peer_interval"
        response = socket.gets
        puts "Response " + response
        if response == "no_interval"
          @peers[ip][:low] = false
          @peers[ip][:high] = false
        else
          response = response.chomp.split(/[,\r\n]/)
          @peers[ip][:low] = response[0].to_i
          @peers[ip][:high] = response[1].to_i
        end
      rescue
      end       
    end
    if @leader_id == nil
      puts "Unable to find the leader"
      exit(1)
    end
    puts "End finding connections"
  end

  def ipscan
    ips = IPAddr.new("192.168." + @ip_digit + ".0/24").to_range
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

case ARGV.length
when 0
  Peer.new(2000)
when 1
  Peer.new(2000, ARGV[0].to_i)
when 2
  Peer.new(2000, ARGV[0].to_i, ARGV[1].to_i)
end