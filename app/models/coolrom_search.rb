require "net/http"
require "nokogiri"
require "timeout"
require "uri"

class CoolromSearch
  class Unavailable < StandardError; end

  MAX_BYTES = 1.megabyte
  MAX_RESULTS = 25
  RESULT_PATH = %r{\A/roms/ps2/[1-9][0-9]*/[^/?#\s]+\.php\z}
  Result = Data.define(:name, :url)

  def search(query)
    uri = URI("https://coolrom.com/search")
    uri.query = URI.encode_www_form(q: query, system: "ps2")
    body = +""
    Timeout.timeout(8, Unavailable) do
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 3, write_timeout: 3, max_retries: 0) do |http|
        request = Net::HTTP::Get.new(uri.request_uri, "Accept" => "text/html", "User-Agent" => "PS2GamesLab/1.0")
        http.request(request) do |response|
          raise Unavailable unless response.is_a?(Net::HTTPSuccess) && response.content_type == "text/html"
          raise Unavailable if response.content_length && response.content_length > MAX_BYTES
          response.read_body do |chunk|
            raise Unavailable if body.bytesize + chunk.bytesize > MAX_BYTES
            body << chunk
          end
        end
      end
    end
    document = Nokogiri::HTML(body)
    heading = document.css(".header").find { |node| node.text.strip == "ROM Search" }
    table = heading&.ancestors&.find { |node| node.name == "table" }
    raise Unavailable unless table && table.xpath(".//text()").map(&:text).join(" ").match?(/\b(?:\d+|No)\s+results? found\b/i)

    table.css("a[href]").filter_map do |link|
      path = link["href"]
      next unless RESULT_PATH.match?(path)
      name = link.text.squish
      next if name.empty?
      Result.new(name: name.first(200), url: "https://coolrom.com#{path}")
    end.uniq(&:url).first(MAX_RESULTS)
  rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError, ArgumentError
    raise Unavailable
  end
end
