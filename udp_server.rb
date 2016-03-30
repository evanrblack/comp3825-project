require 'socket'
Thread.abort_on_exception = true

TIMEOUT = 0.5
AB_DATA_MAX_SIZE = 1024
AB_CHUNK_SIZE = 1 + AB_DATA_MAX_SIZE
AB_PACK_SERVER = "Ca*"
AB_PACK_CLIENT = 'C'

# Log level
LOG_LEVEL = ARGV[0].to_i || 0

def log_puts(ip, port, level, message)
  if level <= LOG_LEVEL
    puts "#{Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")}|#{ip}:#{port}|#{message}"
  end
end

def ab_server(filename, socket)
  ip, port = socket.connect_address.ip_unpack
  last_received = Time.now
  bit = 0
  File.open(filename, 'r') do |f|
    until f.eof?
      data = f.read(AB_DATA_MAX_SIZE)
      chunk = [bit, data].pack(AB_PACK_SERVER)
      log_puts(ip, port, 2, "Sending #{[bit, data]}")
      begin
        data, _ = socket.recvfrom_nonblock(1)
        client_bit = data.unpack('C').first
        last_received = Time.now
        if client_bit == bit
          log_puts(ip, port, 1, 'Received correct bit; advancing...')
          bit = bit^1
        else
          log_puts(ip, port, 1, 'Received incorrect bit; resending...')
          raise 'Bad bit'
        end
      rescue
        #log_puts(ip, port, 3, "Resending #{bit}")
        socket.send(chunk, 0)
        if Time.now - last_received < TIMEOUT
          retry
        else
          log_puts(ip, port, 0, 'Connection timed out')
          break
        end
      end
    end
    socket.send('', 0)
    log_puts(ip, port, 0, 'Sent empty packet for EOF; closing socket...')
    sleep 0.1
    socket.close
  end
end

# TODO: Flood control bits too.
#       This way not

# The main socket blocks waiting for new connections.
# When a packet is received asking for a file, it checks for it.
#
# If it does not exist, the main socket sends a 0 back to the client.
#
# If it does exist, it creates a new socket for an upcoming thread
# and the new socket sends back a 1, giving the client both a confirmation
# and a port for the new socket.
main_socket = UDPSocket.new
main_socket.bind('*', 5024)
while true
  filename, addr = main_socket.recvfrom(255)
  ip, port = addr[3], addr[1]
  if File.exist?(filename)
    log_puts(ip, port, 0, "Request for #{filename}; file found, (#{File.size(filename)} bytes)")
    thread_socket = UDPSocket.new
    thread_socket.connect(ip, port)
    thread_socket.send([1].pack('C'), 0)
    Thread.new { ab_server(filename, thread_socket) }
  else
    log_puts(ip, port, 0, "Request for #{filename}; file not found")
    main_socket.send([0].pack('C'), 0, ip, port)
  end
end
