# frozen_string_literal: true

require "bigdecimal"

module RailsCryptoPayment
  class Error < StandardError; end

  MAX_UNIQUE_CODE = 9999
  CODE_UNIT = BigDecimal("0.000001")

  def self.base_amount(idr:, rate:)
    exchange_rate = BigDecimal(rate.to_s)
    raise ArgumentError, "rate must be positive" unless exchange_rate.positive?

    (BigDecimal(idr.to_s) / exchange_rate).ceil(2)
  end

  def self.amount(base:, code:)
    number = Integer(code)
    raise ArgumentError, "code must be between 1 and #{MAX_UNIQUE_CODE}" unless (1..MAX_UNIQUE_CODE).cover?(number)

    BigDecimal(base.to_s) + number * CODE_UNIT
  end

  def self.available_codes(base:, reserved_amounts:)
    baseline = BigDecimal(base.to_s)
    reserved = reserved_amounts.each_with_object({}) do |value, codes|
      code = (BigDecimal(value.to_s) - baseline) / CODE_UNIT
      codes[code.to_i] = true if code.frac.zero? && (1..MAX_UNIQUE_CODE).cover?(code.to_i)
    end
    (1..MAX_UNIQUE_CODE).reject { |code| reserved.key?(code) }
  end
end

require_relative "rails_crypto_payment/evm_rpc"
require_relative "rails_crypto_payment/exchange_clients"
