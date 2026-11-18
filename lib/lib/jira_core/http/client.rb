# frozen_string_literal: true

require "uri"
require "json"

module JiraCore
  module HTTP
    class Client
      Response = Struct.new(:status, :headers, :body, :uri, keyword_init: true) do
        def success?
          status.between?(200, 299)
        end

        def json
          JSON.parse(body.to_s)
        end
      end

      RETRY_STATUSES = [429, 500, 502, 503, 504].freeze
      MAX_RETRIES = 2

      def initialize(base_url:, timeout_ms: 20_000, keep_alive: true, keep_alive_timeout: 30,
                     open_timeout: 5, logger: nil, default_headers: {})
        @base_uri = URI.parse(base_url.to_s)
        raise ArgumentError, "invalid base URL #{base_url.inspect}" unless @base_uri.scheme && @base_uri.host

        @timeout = timeout_ms / 1000.0
        @keep_alive = keep_alive
        @keep_alive_timeout = keep_alive_timeout
        @open_timeout = open_timeout
        @logger = logger
        @default_headers = default_headers
        @connections = {}
        @mutex = Mutex.new
      end

      def get(path, query: nil, headers: {}, retry_statuses: RETRY_STATUSES)
        request(:get, path, query: query, headers: headers, retry_statuses: retry_statuses)
      end

      def get_json(path, query: nil, headers: {}, retry_statuses: RETRY_STATUSES)
        response = get(path, query: query, headers: headers, retry_statuses: retry_statuses)
        return nil if response.body.nil? || response.body.empty?

        JSON.parse(response.body)
      end

      def request(method, path, query: nil, headers: {}, retry_statuses: RETRY_STATUSES)
        uri = build_uri(path, query)
        attempts = 0
        begin
          attempts += 1
          response = perform(method, uri, headers)
          if retry_statuses.include?(response.status) && attempts <= MAX_RETRIES
            sleep(retry_delay(response, attempts))
            invalidate(origin_key(uri)) if response.status == 429
            raise RetryRequest
          end
          response
        rescue RetryRequest
          retry
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          invalidate(origin_key(uri))
          retry if attempts <= MAX_RETRIES
          raise TimeoutError.new("request timed out: #{e.class}", status: nil)
        rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError => e
          invalidate(origin_key(uri))
          retry if attempts <= MAX_RETRIES
          raise ConnectionError.new("connection failed: #{e.class}", status: nil)
        rescue Errno::ECONNREFUSED, SocketError => e
          invalidate(origin_key(uri))
          raise ConnectionError.new("connection failed: #{e.message}", status: nil)
        end
      end

      def close
        @mutex.synchronize do
          @connections.each_value do |http|
            http.finish if http.started?
          rescue StandardError
            nil
          end
          @connections.clear
        end
      end

      private

      class RetryRequest < StandardError; end

      def perform(_method, uri, headers)
        require "net/http"
        require "openssl"

        http = connection(uri)
        request = Net::HTTP::Get.new(uri.request_uri)
        default_headers.merge(headers).each { |key, value| request[key] = value if value }
        request["Accept"] ||= "application/json"
        raw = http.request(request)
        Response.new(
          status: raw.code.to_i,
          headers: raw.each_header.to_h,
          body: raw.body,
          uri: uri
        )
      end

      def connection(uri)
        key = origin_key(uri)
        @mutex.synchronize do
          http = @connections[key]
          return http if http&.started?

          http = build_http(uri)
          http.start
          @connections[key] = http
          http
        end
      end

      def build_http(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @timeout
        http.write_timeout = @timeout
        http.keep_alive_timeout = @keep_alive_timeout
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
        http
      end

      def invalidate(key)
        @mutex.synchronize do
          http = @connections.delete(key)
          http.finish if http&.started?
        rescue StandardError
          nil
        end
      end

      def origin_key(uri)
        "#{uri.scheme}://#{uri.host}:#{uri.port}"
      end

      def build_uri(path, query)
        text = path.to_s
        if text.start_with?("http://", "https://")
          uri = URI.parse(text)
        else
          base_path = @base_uri.path.to_s
          base_path = "" if base_path == "/"
          full_path = if !base_path.empty? && text.start_with?(base_path)
                        text
                      elsif text.start_with?("/")
                        "#{base_path}#{text}"
                      else
                        "#{base_path}/#{text}"
                      end
          uri = @base_uri.dup
          uri.path = full_path
          uri.query = nil
        end
        if query && !query.empty?
          existing = URI.decode_www_form(uri.query.to_s)
          uri.query = URI.encode_www_form(existing + query.map { |k, v| [k.to_s, v.to_s] })
        end
        uri
      end

      attr_reader :default_headers

      def retry_delay(response, attempts)
        retry_after = response.headers["retry-after"]
        if retry_after
          value = retry_after.to_s.strip
          seconds = value.match?(/\A\d+(\.\d+)?\z/) ? value.to_f : 1.0
          return [seconds, 5.0].min
        end
        [0.2 * (2**(attempts - 1)), 2.0].min
      end
    end
  end
end
