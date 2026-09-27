# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require_relative "../lib/rails_crypto_payment"

class ExchangeClientsTest < Minitest::Test
  def response(body)
    Net::HTTPOK.new("1.1", "200", "OK").tap do |result|
      result.instance_variable_set(:@read, true)
      result.body = JSON.generate(body)
    end
  end

  def fake_http(&handler)
    Object.new.tap { |http| http.define_singleton_method(:request) { |request| handler.call(request) } }
  end

  def test_binance_signs_query_and_selects_internal_reference
    http = fake_http do |request|
      params = URI.decode_www_form(request.path.split("?", 2).last).to_h
      signature = params.delete("signature")
      query = request.path.split("?", 2).last.sub(/&signature=[^&]+\z/, "")
      assert_equal OpenSSL::HMAC.hexdigest("SHA256", "secret", query), signature
      assert_equal "key", request["X-MBX-APIKEY"]
      assert_equal "USDT", params["coin"]
      response([{ "txId" => "OTHER", "transferType" => 1 },
        { "txId" => "ABC", "transferType" => 0 }, { "txId" => "ABC", "transferType" => 1 }])
    end
    Net::HTTP.stub(:start, ->(*_args, **_options, &block) { block.call(http) }) do
      assert_equal "ABC", RailsCryptoPayment::BinanceDepositClient.new(key: "key", secret: "secret")
        .find_internal_usdt(tx_id: "abc", start_time: 10, end_time: 20).fetch("txId")
    end
  end

  def test_bybit_signs_and_paginates_internal_deposits
    seen = []
    http = fake_http do |request|
      params = URI.decode_www_form(request.path.split("?", 2).last).to_h
      assert_equal "USDT", params["coin"]
      assert_equal "key", request["X-BAPI-API-KEY"]
      assert_equal OpenSSL::HMAC.hexdigest("SHA256", "secret",
        "#{request['X-BAPI-TIMESTAMP']}key5000#{request.path.split('?', 2).last}"), request["X-BAPI-SIGN"]
      seen << params["cursor"]
      response({ "retCode" => 0, "result" => { "rows" => [{ "amount" => "1" }],
        "nextPageCursor" => seen.length == 1 ? "next" : "" } })
    end
    Net::HTTP.stub(:start, ->(*_args, **_options, &block) { block.call(http) }) do
      assert_equal [{ "amount" => "1" }, { "amount" => "1" }],
        RailsCryptoPayment::BybitDepositClient.new(key: "key", secret: "secret").internal_deposits(start_time: 10)
    end
    assert_equal [nil, "next"], seen
  end

  def test_wraps_exchange_transport_failures
    Net::HTTP.stub(:start, ->(*_args, **_options) { raise Net::ReadTimeout }) do
      assert_raises(RailsCryptoPayment::Error) do
        RailsCryptoPayment::BinanceDepositClient.new(key: "key", secret: "secret")
          .find_internal_usdt(tx_id: "tx", start_time: 10, end_time: 20)
      end
      assert_raises(RailsCryptoPayment::Error) do
        RailsCryptoPayment::BybitDepositClient.new(key: "key", secret: "secret").internal_deposits(start_time: 10)
      end
    end
  end

  def test_wraps_malformed_bybit_result
    [{ "retCode" => 0 }, { "retCode" => 0, "result" => { "rows" => nil } }].each do |body|
      http = fake_http { |_request| response(body) }
      Net::HTTP.stub(:start, ->(*_args, **_options, &block) { block.call(http) }) do
        error = assert_raises(RailsCryptoPayment::Error) do
          RailsCryptoPayment::BybitDepositClient.new(key: "key", secret: "secret").internal_deposits(start_time: 10)
        end
        assert_match "Bybit API response invalid", error.message
      end
    end
  end
end
