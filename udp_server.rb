require 'socket'

Thread.abort_on_exception = true

TIMEOUT = 1.0
PROTOCOLS = { 'ab' => :ab_server, 'gbn' => :gbn_server }

LOG_LEVEL = ARGV[0].to_i || 0

def log_puts(ip, port, level, message)
  if level <= LOG_LEVEL
    puts "#{Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")}|#{ip}:#{port}|#{message}"
  end
end

AB_DATA_MAX_SIZE = 64
AB_CHUNK_SIZE = 1 + AB_DATA_MAX_SIZE
AB_PACK_SERVER = "Ca*"
AB_PACK_CLIENT = 'C'

def ab_server(filename, socket)
  ip, port = socket.remote_address.ip_unpack
  last_received = Time.now
  bit = 0
  closing = false
  File.open(filename, 'r') do |f|
    while true
      data = (f.eof? ? '' : f.read(AB_DATA_MAX_SIZE))
      chunk = [bit, data].pack(AB_PACK_SERVER)
      begin
        message = socket.recv_nonblock(1)
        if data == '' and !closing
          log_puts(ip, port, 0, 'Sending empty data for EOF; closing socket...')
          closing = true
        end

        client_bit = message.unpack('C').first
        last_received = Time.now
        if client_bit == bit
          log_puts(ip, port, 1, 'Received correct bit; advancing...')
          bit = bit^1
        else
          log_puts(ip, port, 1, 'Received incorrect bit; sending...')
          raise 'Bad bit'
        end
      rescue
        log_puts(ip, port, 3, "Sending \"#{chunk}\"")
        socket.send(chunk, 0)
        if Time.now - last_received < TIMEOUT
          retry
        else
          log_puts(ip, port, 0, 'Connection timed out') if !closing
          break
        end
      end
    end
    socket.close()
  end
end

GBN_DATA_MAX_SIZE = 64
GBN_CHUNK_SIZE = 4 + GBN_DATA_MAX_SIZE
GBN_PACK_SERVER = 'La*'
GBN_PACK_CLIENT = 'L'
GBN_WINDOW_SIZE = 5
# L == unsigned 32-bit int

def gbn_server(filename, socket)
  ip, port = socket.remote_address.ip_unpack

  # Break file into an array of strings of length <= GBN_DATA_MAX_SIZE
  file = []
  File.open(filename) do |f|
    while !f.eof?
      file << f.read(GBN_DATA_MAX_SIZE)
    end
  end

  seq_base = 0
  seq_max = file.length - 1
  last_received = Time.now
  while true
    
    # Receive
    begin
      received = socket.recv_nonblock(4)  # 32 bit number
      req_num = received.unpack(GBN_PACK_CLIENT).first
      last_received = Time.now
      if req_num > seq_base
        log_puts(ip, port, 1, "Received ACK for #{req_num}/#{seq_max}; moving window up...")
        seq_base = req_num
      else
        log_puts(ip, port, 1, "Received ACK for #{req_num}/#{seq_max}; keeping window at #{seq_base}...")
      end
      
      if seq_base == seq_max
        log_puts(ip, port, 0, 'Received ACK for EOF; closing socket...')
        break
      end
    rescue
      if Time.now - last_received > TIMEOUT
        log_puts(ip, port, 0, 'Timed out...')
        break
      end
    end

    # Send
    begin
      GBN_WINDOW_SIZE.times do |n|
        if (seq_send = seq_base + n) <= seq_max
          chunk = [seq_send, file[seq_send]].pack(GBN_PACK_SERVER)
          log_puts(ip, port, 2, "Sending \"#{chunk}\"")
        else  # we're at the end, send the blank packet
          chunk = [seq_send, ''].pack(GBN_PACK_SERVER)
          log_puts(ip, port, 2, 'Sending EOF...')
        end
        socket.send(chunk, 0)
      end
    rescue
      # Do nothing
    end
  end
  socket.close
end

# The main socket blocks waiting for new connections.
# When a packet is received asking for a file, it checks for it.
#
# If it does not exist, the main socket sends an empty packet back to the client.
#
# If it does exist, it creates a new socket for an upcoming thread
# and the new socket sends back the initial data, giving the client
# data and the port for the new socket.
main_socket = UDPSocket.new
main_socket.bind('*', 5024)
while true
  data, addr = main_socket.recvfrom(255)
  protocol, filename = data.split
  ip, port = addr[3], addr[1]
  if File.exist?(filename)
    log_puts(ip, port, 0, "Request for #{filename} over #{protocol}; file found, (#{File.size(filename)} bytes)")
    thread_socket = UDPSocket.new
    thread_socket.connect(ip, port)
    Thread.new { send(PROTOCOLS[protocol], filename, thread_socket) }
  else
    log_puts(ip, port, 0, "Request for #{filename}; file not found")
    main_socket.send('', 0, ip, port)
  end
end
