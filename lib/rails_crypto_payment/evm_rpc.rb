# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RailsCryptoPayment
  class EvmRpc
    TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    class RpcError < Error
      attr_reader :code

      def initialize(code, message)
        @code = code
        super("RPC error #{code}: #{message}")
      end
    end

    def initialize(url:, username: nil, password: nil)
      @uri = URI(url.to_s)
      raise ArgumentError, "RPC URL must use HTTP or HTTPS" unless %w[http https].include?(@uri.scheme)
      raise ArgumentError, "RPC username and password must be provided together" if username.to_s.empty? != password.to_s.empty?
      raise ArgumentError, "Credentialed RPC URL must use HTTPS" if @uri.scheme != "https" && !username.to_s.empty?

      @username = username
      @password = password
    end

    def call(method, params)
      request = Net::HTTP::Post.new(@uri, "Content-Type" => "application/json")
      request.basic_auth(@username, @password) if @username && @password
      request.body = { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json
      response = Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == "https", open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      raise Error, "RPC HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      raise RpcError.new(body["error"]["code"], body["error"]["message"]) if body["error"]

      body.fetch("result")
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "RPC request failed: #{e.message}"
    end

    def transfer_logs(from_block:, to_block:, token:, wallets:)
      raise ArgumentError, "from_block must not exceed to_block" if from_block > to_block

      topics = wallets.map { |wallet| "0x#{wallet.delete_prefix('0x').downcase.rjust(64, '0')}" }
      call("eth_getLogs", [{ fromBlock: "0x#{from_block.to_s(16)}", toBlock: "0x#{to_block.to_s(16)}",
        address: token, topics: [TRANSFER, nil, topics] }])
    rescue RpcError => e
      raise unless e.code == -32_005 && from_block < to_block

      middle = (from_block + to_block) / 2
      transfer_logs(from_block: from_block, to_block: middle, token: token, wallets: wallets) +
        transfer_logs(from_block: middle + 1, to_block: to_block, token: token, wallets: wallets)
    end

    def valid_transfer?(log:, token:)
      return false if log["removed"] || !log.fetch("address").casecmp?(token) ||
        !log.fetch("topics").first.casecmp?(TRANSFER)

      receipt = call("eth_getTransactionReceipt", [log.fetch("transactionHash")])
      receipt && receipt["status"] == "0x1" && receipt.fetch("logs").any? do |entry|
        entry["logIndex"] == log["logIndex"] && entry.fetch("address").casecmp?(token) &&
          entry["topics"] == log["topics"] && entry["data"] == log["data"]
      end
    end

    def transfer_amount(log, decimals:)
      scale = Integer(decimals)
      raise ArgumentError, "decimals must be nonnegative" if scale.negative?

      BigDecimal(Integer(log.fetch("data"), 16).to_s) / 10**scale
    end

    def block_time(log)
      block = call("eth_getBlockByNumber", [log.fetch("blockNumber"), false])
      Time.at(Integer(block.fetch("timestamp"), 16)).utc
    end
  end
end
