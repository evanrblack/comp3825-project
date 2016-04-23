require 'socket'
TIMEOUT = 1.0
PROTOCOLS = { 'ab' => :ab_client, 'gbn' => :gbn_client }


AB_DATA_MAX_SIZE = 64
AB_CHUNK_SIZE = 1 + AB_DATA_MAX_SIZE
AB_PACK_SERVER = "Ca*"
AB_PACK_CLIENT = 'C'

def ab_client(socket)
  last_received = Time.now
  bit = 1  # Starts alternate of the server so it doesn't start confirming the first chunk
  while true
    begin
      data = socket.recv_nonblock(AB_CHUNK_SIZE)
      server_bit, message = data.unpack(AB_PACK_SERVER)
      last_received = Time.now
      if server_bit != bit
        if message == ''
          STDERR.puts '-'*16
          STDERR.puts 'File fully transmitted'
          break
        end
        print message
        bit = server_bit
      else
        #puts 'Bad bit'
        raise 'Bad bit'
      end
    rescue
      #puts "RESENDING #{bit}"
      socket.send([bit].pack('C'), 0)
      if Time.now - last_received < TIMEOUT
        retry
      else
        STDERR.puts '-'*16
        STDERR.puts 'Connection timed out'
        break
      end
    end
  end
end


GBN_DATA_MAX_SIZE = 64
GBN_CHUNK_SIZE = 4 + GBN_DATA_MAX_SIZE
GBN_PACK_SERVER = 'La*'
GBN_PACK_CLIENT = 'L'
# L == unsigned 32-bit int

def gbn_client(socket)
  last_received = Time.now
  req_num = 0
  while true
    begin
      received = socket.recv_nonblock(GBN_CHUNK_SIZE)
      seq_num, data = received.unpack(GBN_PACK_SERVER)
      last_received = Time.now
      if seq_num == req_num
        if data == ''
          STDERR.puts '-'*16
          STDERR.puts 'File fully transmitted'
          break
        else
          print data
        end
        req_num += 1
      end
      socket.send([req_num].pack(GBN_PACK_CLIENT), 0)
    rescue
      if Time.now - last_received > TIMEOUT
        STDERR.puts '-'*16
        STDERR.puts 'Connection timed out'
        break
      end
    end
  end
  socket.close
end

host = ARGV[0]
protocol = ARGV[1]
abort('Unknown protocol') unless PROTOCOLS.keys.include? protocol
filename = ARGV[2]

socket = UDPSocket.new
socket.send("#{protocol} #{filename}", 0, host, 5024)
STDERR.puts "Sent request to #{host} for #{filename} over #{protocol}"

start_time = Time.now

while start_time + TIMEOUT > Time.now
  begin
    data, addr = socket.recvfrom_nonblock(1)
  rescue
    # Do nothing
  end
end

if addr.nil?
  abort('Could not connect to server')
end

if data == ''
  STDERR.puts "#{filename} is not a valid file"
else
  STDERR.puts "#{filename} is a valid file, being served from #{addr[3]}:#{addr[1]}"
  STDERR.puts '-'*16
  socket.connect(addr[3], addr[1])
  send("#{ARGV[1]}_client", socket)
end
