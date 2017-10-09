require 'socket'

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
      if (addr_info.ip_addres =~ /192.168.*.*/) == 0
        @id = addr_info.ip_address
      end 
    end
    puts @id
    if @id == nil
      puts "Erro, deveria existir uma interface lan com ip 192.168.*.*"
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
    while not shutdown
      handle(@server.accept)
    end
  end

  def handle(socket)
    
  end

  def receive_message(id)

  end

  def primalitiy_test
    Thread.new {
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
    }
  end

  def connect_leader
    for i in 0..255
        hostname = "192.168.1." + i.to_s
        if (s = TCPSocket.open(hostname, @port))
          s.puts "are_you_leader?"
          answer = s.gets
          if answer == "yes"
            puts "A maquina se conectou ao lider"
            s.puts "fetch_id"
            @leader_id = s.gets 
            puts "Id do líder:" + @leader_id.to_s
          end
          s.close
      end
    end
  end

  def leader_election
  end
end

if ARGV[0] == nil 
  Peer.new(2000)
else 
  Peer.new(2000, ARGV[0].to_i)
end