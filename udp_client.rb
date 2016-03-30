require 'socket'

TIMEOUT = 0.5

AB_DATA_MAX_SIZE = 1024
AB_CHUNK_SIZE = 1 + AB_DATA_MAX_SIZE
AB_PACK_SERVER = "Ca*"
AB_PACK_CLIENT = 'C'

def ab_client(socket)
  last_received = Time.now
  bit = 1  # Starts alternate of the server so it doesn't start confirming the first chunk
  while true
    begin
      data = socket.recv_nonblock(AB_CHUNK_SIZE)
      if data == ''
        STDERR.puts 'File fully transmitted'
        break
      end
      server_bit, message = data.unpack(AB_PACK_SERVER)
      last_received = Time.now
      if server_bit != bit
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
        STDERR.puts('Connection timed out')
        break
      end
    end
  end
end


host = ARGV[0]
filename = ARGV[1]
socket = UDPSocket.new
socket.send(filename, 0, host, 5024)
STDERR.puts "Sent request to #{host} for #{filename}"
data, addr = socket.recvfrom(1)
result = data.unpack('C').first

if result == 0
  STDERR.puts "#{filename} is not a valid file"
else
  STDERR.puts "#{filename} is a valid file, being served from #{addr[3]}:#{addr[1]}"
  socket.connect(addr[3], addr[1])
  ab_client(socket)
end
