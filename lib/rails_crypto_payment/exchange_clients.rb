# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module RailsCryptoPayment
  class BinanceDepositClient
    API = URI("https://api.binance.com")

    def initialize(key:, secret:)
      @key = key.to_s
      @secret = secret.to_s
      raise Error, "Binance API credentials missing" if @key.empty? || @secret.empty?
    end

    def find_internal_usdt(tx_id:, start_time:, end_time:)
      params = { coin: "USDT", status: 1, startTime: start_time, endTime: end_time,
        includeSource: true, recvWindow: 5000, timestamp: (Time.now.to_f * 1000).to_i }
      query = URI.encode_www_form(params)
      signature = OpenSSL::HMAC.hexdigest("SHA256", @secret, query)
      uri = URI("#{API}/sapi/v1/capital/deposit/hisrec?#{query}&signature=#{signature}")
      request = Net::HTTP::Get.new(uri, "X-MBX-APIKEY" => @key)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      raise Error, "Binance API HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).find { |row| row["txId"].to_s.casecmp?(tx_id.to_s) && row["transferType"].to_i == 1 }
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "Binance API request failed: #{e.message}"
    end
  end

  class BybitDepositClient
    API = URI("https://api.bybit.com")
    RECV_WINDOW = "5000"

    def initialize(key:, secret:)
      @key = key.to_s
      @secret = secret.to_s
      raise Error, "Bybit API credentials missing" if @key.empty? || @secret.empty?
    end

    def internal_deposits(start_time:)
      rows = []
      cursor = nil
      loop do
        params = { coin: "USDT", startTime: start_time, limit: 50 }
        params[:cursor] = cursor unless cursor.nil? || cursor.empty?
        result = get("/v5/asset/deposit/query-internal-record", params).fetch("result")
        rows.concat(result.fetch("rows", []))
        cursor = result["nextPageCursor"]
        break if cursor.nil? || cursor.empty?
      end
      rows
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "Bybit API response invalid: #{e.message}"
    end

    private

    def get(path, params)
      query = URI.encode_www_form(params)
      timestamp = (Time.now.to_f * 1000).to_i.to_s
      signature = OpenSSL::HMAC.hexdigest("SHA256", @secret, "#{timestamp}#{@key}#{RECV_WINDOW}#{query}")
      uri = URI("#{API}#{path}?#{query}")
      request = Net::HTTP::Get.new(uri, "X-BAPI-API-KEY" => @key, "X-BAPI-TIMESTAMP" => timestamp,
        "X-BAPI-RECV-WINDOW" => RECV_WINDOW, "X-BAPI-SIGN" => signature)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      raise Error, "Bybit API HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      raise Error, "Bybit API error #{body['retCode']}: #{body['retMsg']}" unless body["retCode"] == 0

      body
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "Bybit API request failed: #{e.message}"
    end
  end
end
