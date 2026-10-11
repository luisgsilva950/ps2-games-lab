require "socket"
require "json"
class ModelEndpoint
  attr_reader :requests
  def initialize(status: 200, delay: 0)
    @status, @delay = status, delay
    @requests = Queue.new
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new do
      loop do
        socket = @server.accept
        first = socket.gets
        headers = {}
        while (line = socket.gets) && line != "\r\n"
          key, value = line.split(":", 2)
          headers[key.downcase] = value.strip
        end
        body = JSON.parse(socket.read(headers.fetch("content-length", "0").to_i))
        @requests << { path: first.split[1], body: body }
        if @status == 200
          socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n")
          [ "No image changes were performed. ", "Start by identifying the game's revision and handling data." ].each do |text|
            event = { id: "fixture", model: "lab-model", choices: [ { index: 0, delta: { role: "assistant", content: text }, finish_reason: nil } ] }
            socket.write("data: #{JSON.generate(event)}\n\n")
            sleep @delay
          end
          socket.write("data: #{JSON.generate({ model: "lab-model", choices: [ { index: 0, delta: {}, finish_reason: "stop" } ] })}\n\ndata: [DONE]\n\n")
        else
          bytes = JSON.generate(error: { message: "private-provider-detail api-key-secret", type: "invalid_request_error", code: "invalid_api_key" })
          socket.write("HTTP/1.1 #{@status} Response\r\nContent-Type: application/json\r\nContent-Length: #{bytes.bytesize}\r\nConnection: close\r\n\r\n#{bytes}")
        end
        socket.close
      end
    rescue IOError, Errno::EBADF
    end
  end
  def base_url
    "http://127.0.0.1:#{@server.addr[1]}/v1"
  end
  def close
    @server.close
    @thread.kill
    @thread.join
  end
end
