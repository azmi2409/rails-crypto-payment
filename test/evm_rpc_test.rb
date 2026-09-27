# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rails_crypto_payment"

class EvmRpcTest < Minitest::Test
  class FakeRpc < RailsCryptoPayment::EvmRpc
    attr_reader :requests

    def initialize(&response)
      super(url: "https://rpc.example")
      @response = response
      @requests = []
    end

    def call(method, params)
      @requests << [method, params]
      @response.call(method, params)
    end
  end

  def test_splits_range_on_limit_error_and_preserves_wallet_filter
    rpc = FakeRpc.new do |method, params|
      range = params.first
      raise RailsCryptoPayment::EvmRpc::RpcError.new(-32_005, "range too large") if range[:fromBlock] == "0x1" && range[:toBlock] == "0x4"

      [range[:fromBlock], range[:toBlock]]
    end
    assert_equal %w[0x1 0x2 0x3 0x4], rpc.transfer_logs(from_block: 1, to_block: 4,
      token: "0xToken", wallets: ["0xABC"])
    assert_equal [RailsCryptoPayment::EvmRpc::TRANSFER, nil, ["0x#{'0' * 61}abc"]],
      rpc.requests.first.last.first[:topics]
  end

  def test_verifies_receipt_log_and_decodes_amount_and_time
    log = { "transactionHash" => "0xhash", "blockNumber" => "0x10", "logIndex" => "0x2",
      "address" => "0xTOKEN", "topics" => [RailsCryptoPayment::EvmRpc::TRANSFER, "from", "to"],
      "data" => "0xf4240" }
    rpc = FakeRpc.new do |method, _params|
      method == "eth_getTransactionReceipt" ? { "status" => "0x1", "logs" => [log] } : { "timestamp" => "0x64" }
    end
    assert rpc.valid_transfer?(log: log, token: "0xtoken")
    assert_equal BigDecimal("1"), rpc.transfer_amount(log, decimals: 6)
    assert_equal Time.at(100).utc, rpc.block_time(log)
    refute rpc.valid_transfer?(log: log.merge("removed" => true), token: "0xtoken")
  end

  def test_rejects_other_receipt_log_and_terminal_range_error
    log = { "transactionHash" => "0xhash", "logIndex" => "0x1", "address" => "0xtoken",
      "topics" => [RailsCryptoPayment::EvmRpc::TRANSFER], "data" => "0x1" }
    rpc = FakeRpc.new do |method, _params|
      if method == "eth_getLogs"
        raise RailsCryptoPayment::EvmRpc::RpcError.new(-32_005, "too many")
      end
      { "status" => "0x1", "logs" => [log.merge("data" => "0x2")] }
    end
    refute rpc.valid_transfer?(log: log, token: "0xtoken")
    assert_raises(RailsCryptoPayment::EvmRpc::RpcError) do
      rpc.transfer_logs(from_block: 1, to_block: 1, token: "0xtoken", wallets: ["0xabc"])
    end
  end

  def test_rejects_partial_or_plaintext_credentials
    assert_raises(ArgumentError) { RailsCryptoPayment::EvmRpc.new(url: "https://rpc.example", username: "user") }
    assert_raises(ArgumentError) do
      RailsCryptoPayment::EvmRpc.new(url: "http://rpc.example", username: "user", password: "secret")
    end
  end

  def test_wraps_transport_failures
    Net::HTTP.stub(:start, ->(*_args, **_options) { raise Net::ReadTimeout }) do
      error = assert_raises(RailsCryptoPayment::Error) do
        RailsCryptoPayment::EvmRpc.new(url: "https://rpc.example").call("eth_blockNumber", [])
      end
      assert_match "RPC request failed", error.message
    end
  end
end
