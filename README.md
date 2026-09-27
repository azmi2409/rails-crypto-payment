# rails-crypto-payment

Standalone Ruby library for exact USDT payment amounts and deposit retrieval. No Rails or database dependency. Host application owns credentials, wallet configuration, payment records, polling cursor, expiration, settlement, transaction locking, and jobs.

Install dependencies with `bundle install`. Build release with `gem build rails-crypto-payment.gemspec`. Malformed Bybit result data raises `RailsCryptoPayment::Error`, like transport and API failures.

```ruby
require "rails_crypto_payment"

base = RailsCryptoPayment.base_amount(idr: 50_000, rate: "16000") # BigDecimal("3.13")
reserved = RailsCryptoPayment.available_codes(base: base, reserved_amounts: ["3.130001"])
code = reserved.sample(random: Random::DEFAULT)
amount = RailsCryptoPayment.amount(base: base, code: code) # exact six-decimal BigDecimal
# Persist reservation under database uniqueness constraint; retry another code on conflict.
```

`base_amount` rounds quotient upward to two decimals; codes 1..9999 add increments of 0.000001 USDT. `available_codes` excludes only exact amount matches within this range. Application must scope reserved amounts by payment gateway and enforce uniqueness atomically.

## EVM transfers (BSC, Plasma, testnets)

```ruby
rpc = RailsCryptoPayment::EvmRpc.new(url: "https://rpc.example", username: ENV["RPC_USER"], password: ENV["RPC_PASS"])
latest = Integer(rpc.call("eth_blockNumber", []), 16)
logs = rpc.transfer_logs(from_block: latest - 100, to_block: latest - 12,
  token: "0x55d398326f99059ff775485246999027b3197955", wallets: ["0xYourWallet"])
logs.each do |log|
  next unless rpc.valid_transfer?(log: log, token: "0x55d398326f99059ff775485246999027b3197955")
  amount = rpc.transfer_amount(log, decimals: 18)
  time = rpc.block_time(log)
  # Match recipient ("0x#{log.fetch('topics').fetch(2).last(40)}"), amount, time and gateway
  # against an unpaid reservation before transactional settlement.
end
```

`transfer_logs` filters token, ERC-20 Transfer topic and recipient wallets. RPC `-32005` range errors split block ranges; single-block errors propagate. `valid_transfer?` confirms successful transaction receipt and matching log. `transfer_amount` uses token decimals (BSC USDT uses 18; app test tokens may use 6). Credentialed RPC requires HTTPS. Transport, HTTP, and malformed-response failures raise `RailsCryptoPayment::Error`; JSON-RPC failures raise `RailsCryptoPayment::EvmRpc::RpcError` with `code`.

## Exchange internal deposits

```ruby
binance = RailsCryptoPayment::BinanceDepositClient.new(key: ENV.fetch("BINANCE_KEY"), secret: ENV.fetch("BINANCE_SECRET"))
row = binance.find_internal_usdt(tx_id: submitted_reference, start_time: from_ms, end_time: to_ms)
# Check row status, coin, amount and timestamp against reservation before settlement.

bybit = RailsCryptoPayment::BybitDepositClient.new(key: ENV.fetch("BYBIT_KEY"), secret: ENV.fetch("BYBIT_SECRET"))
rows = bybit.internal_deposits(start_time: from_ms)
# Check each row status, coin, amount and timestamp against unpaid reservations.
```

Binance returns matching internal-transfer deposit or `nil`; Bybit paginates and returns all rows. Clients sign requests with provided credentials, never read Rails credentials. Transport, HTTP, malformed-response, and API failures raise `RailsCryptoPayment::Error`.

Run all focused checks with `bundle exec ruby -Ilib:test -e 'Dir["test/*_test.rb"].each { |file| require_relative file }'`.
