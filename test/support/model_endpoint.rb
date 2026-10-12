require "socket"
require "json"

class ModelEndpoint
  REPLY_PARTS = [ "No image changes were performed. ", "Start by identifying the game's revision and handling data." ].freeze

  attr_reader :requests

  def initialize(status: 200, delay: 0, provider: "openai")
    @status, @delay, @provider = status, delay, provider
    @requests = Queue.new
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new do
      loop do
        socket = @server.accept
        begin
          first = socket.gets
          headers = {}
          while (line = socket.gets) && line != "\r\n"
            key, value = line.split(":", 2)
            headers[key.downcase] = value.strip
          end
          body = JSON.parse(socket.read(headers.fetch("content-length", "0").to_i))
          @requests << { method: first.split[0], path: first.split[1], headers: headers, body: body }
          @status == 200 ? write_stream(socket) : write_error(socket)
        ensure
          socket.close
        end
      end
    rescue IOError, Errno::EBADF
    end
  end

  def base_url
    version = @provider == "gemini" ? "v1beta" : "v1"
    "http://127.0.0.1:#{@server.addr[1]}/#{version}"
  end

  def close
    @server.close
    @thread.kill
    @thread.join
  end

  private

  def write_stream(socket)
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n")
    REPLY_PARTS.each do |text|
      event = if @provider == "gemini"
        { modelVersion: "gemini-2.5-flash", candidates: [ { index: 0, content: { role: "model", parts: [ { text: text } ] } } ] }
      else
        { id: "fixture", model: "lab-model", choices: [ { index: 0, delta: { role: "assistant", content: text }, finish_reason: nil } ] }
      end
      socket.write("data: #{JSON.generate(event)}\n\n")
      sleep @delay
    end
    if @provider == "gemini"
      event = { modelVersion: "gemini-2.5-flash", candidates: [ { index: 0, finishReason: "STOP" } ], usageMetadata: { promptTokenCount: 20, candidatesTokenCount: 16 } }
      socket.write("data: #{JSON.generate(event)}\n\n")
    else
      socket.write("data: #{JSON.generate({ model: "lab-model", choices: [ { index: 0, delta: {}, finish_reason: "stop" } ] })}\n\ndata: [DONE]\n\n")
    end
  end

  def write_error(socket)
    detail = "private-provider-detail api-key-secret gemini-key-secret"
    error = if @provider == "gemini"
      { error: { code: @status, message: detail, status: "PERMISSION_DENIED" } }
    else
      { error: { message: detail, type: "invalid_request_error", code: "invalid_api_key" } }
    end
    bytes = JSON.generate(error)
    socket.write("HTTP/1.1 #{@status} Response\r\nContent-Type: application/json\r\nContent-Length: #{bytes.bytesize}\r\nConnection: close\r\n\r\n#{bytes}")
  end
end
