# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rails_crypto_payment"

class RailsCryptoPaymentTest < Minitest::Test
  def test_rounds_base_up_and_preserves_six_decimal_codes
    base = RailsCryptoPayment.base_amount(idr: 10_001, rate: 16_000)
    assert_equal BigDecimal("0.63"), base
    assert_equal BigDecimal("0.630001"), RailsCryptoPayment.amount(base: base, code: 1)
    assert_equal BigDecimal("0.639999"), RailsCryptoPayment.amount(base: base, code: 9999)
  end

  def test_available_codes_ignore_out_of_range_and_fractional_reservations
    codes = RailsCryptoPayment.available_codes(base: BigDecimal("1.25"),
      reserved_amounts: [BigDecimal("1.250001"), BigDecimal("1.259999"), "1.2500015", "1.26", "1.25"])
    refute_includes codes, 1
    refute_includes codes, 9999
    assert_includes codes, 2
    assert_equal 9997, codes.size
  end

  def test_rejects_invalid_rate_and_code
    assert_raises(ArgumentError) { RailsCryptoPayment.base_amount(idr: 1, rate: 0) }
    assert_raises(ArgumentError) { RailsCryptoPayment.amount(base: 1, code: 0) }
    assert_raises(ArgumentError) { RailsCryptoPayment.amount(base: 1, code: 10_000) }
  end
end
