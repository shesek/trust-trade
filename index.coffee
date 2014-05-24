{ sha256 } = require 'crypto-hashing'
{ buff_eq, format_satoshis, pj } = require './lib/util'
Key = require './lib/key'
Channel = require './channel'
pushtx = require './pushtx'
sign_multisig = require './lib/sign-multisig'
readline = require 'readline'

debug = require('debug')('info')
debug_bob = require('debug')('bob')
debug_alice = require('debug')('alice')
debug_arb = require('debug')('arbitrator')

exchange_rates = BTC: 20, 'BTC-TEST': 0.05
num_trades = 15

# The parties Kkeys
a_key = Key.from_priv sha256 'alice_'
b_key = Key.from_priv sha256 'bob_'
arb_key = Key.from_priv sha256 'arb_'

addr = require './lib/addr'

#for user, key of { Alice: a_key, Bob: b_key, Arb: arb_key }
#  for asset in ['BTC','BTC-TEST']
#    debug '[%s] %s - privkey: %s, addr: %s, pubkey: %s', asset, user, (addr.encode asset, 'private', key.priv), (addr.encode asset, 'public', key.pub), key.pub.toString('hex')

# Alice's initial assets and refund addresses for each
a_assets =
  BTC:
    cap: 100000 # 0.001 BTC
    address: '1KAuhh8SNrHsHeTQAMvW6Bx3iKZiAGNhB2'
  'BTC-TEST':
    cap: 2000000 # 0.02 BTC
    address: 'mrg1bs9GCHJo6yZLooCc1UESHKcBgoLK4y'

# Alice's funding txs (just hardcoded for now, should be provided in realtime)
a_funding =
  BTC: txid: '5d14c144b2641c358382ab116c21a76d2f119e784c5d31dd3450be0c48f8678b', index: 0
  'BTC-TEST': txid: '26ba4a455626d264aad07b14db26b719e5df98638a0826361bed81a9b409163f', index: 0

# Bob's initial assets and refund addresses for each
b_assets =
  BTC:
    cap: 100000 # 0.001 BTC
    address: '1EJcxdG5k2KMpGh5KUfVhKy2oqpE2ipYpv'
  'BTC-TEST':
    cap: 2000000 # 0.02 BTC
    address: 'mrg1bs9GCHJo6yZLooCc1UESHKcBgoLK4y'

# Bob's funding txs (just hardcoded for now, should be provided in realtime)
b_funding =
  BTC: txid: '28d03c797e186ed842d1b1391dae5737c77c30642d088aeafdd43d6542f19c0a', index: 0
  'BTC-TEST': txid: 'c0df8c8738e7daaebda09b12ac117a2e93435ff919c85cf52541a6397c2276f5', index: 0

create_channel = ->
  # 1. Alice: initiate channel and create handshake
  # A: { A_pubkey, A_assets, expires } -> B
  a_handshake =
    expires: Date.now() + 86400 # 24h
    pubkey: a_key.pub
    assets: a_assets

  debug_alice 'Handshake: %j', a_handshake
  # a_handshake -> Bob over network...

  # 2. Bob: handshake reply
  # B: { B_pubkey, B_assets, B_funding, scripthash } -> A

  # Create channel from Bob's perspective
  b_channel = new Channel b_key,
    expires: a_handshake.expires
    my_assets: b_assets
    other_assets: a_handshake.assets
    other_key: Key.from_pub a_handshake.pubkey
    arb_key: Key.from_pub arb_key.pub
  b_channel.add_funding b_funding

  b_handshake_reply =
    pubkey: b_key.pub
    assets: b_assets
    funding: b_funding
    scripthash: sha256 b_channel.multisig_script().buffer

  debug_bob 'Handshake reply: %j', b_handshake_reply
  # b_handshake_reply -> Alice over network...

  # 3. Alice: provide redeems and ask for ones
  # A: { A_funding, B_redeems } -> B

  # Create channel from Alice's perspective
  a_channel = new Channel a_key,
    expires: a_handshake.expires
    my_assets: a_assets
    other_assets: b_handshake_reply.assets
    other_key: Key.from_pub b_handshake_reply.pubkey
    arb_key: Key.from_pub arb_key.pub
  a_channel.add_funding a_funding
  a_channel.add_funding b_handshake_reply.funding

  # Validate the recieved scripthash matches the local one
  unless buff_eq (sha256 a_channel.multisig_script().buffer), b_handshake_reply.scripthash
    throw new Error 'Multi-signature script does not match'

  debug_alice 'Funding with: %j', a_funding

  # Sign requested redeems for Bob assets
  b_redeems = a_channel.make_redeems a_channel.other_assets, b_handshake_reply.funding, true
  debug_alice 'Created redeems for Bob'

  # a_funding & b_redeems -> Bob over network...

  # 4. Bob: validate provided redeems and send redeems to Alice
  # B: { A_redeems } -> A
  unless b_channel.validate_redeems b_redeems
    throw new Error 'Invalid redeems provided by Alice'

  debug_bob 'Validated redeems from Alice'

  a_redeems = b_channel.make_redeems a_channel.other_assets, a_funding, true
  b_channel.add_funding a_funding

  # a_redeems -> Alice over network...

  # 5. Alice: validate provided redeems

  unless a_channel.validate_redeems a_redeems
    throw new Error 'Invalid redeems provided by Bob'

  debug_alice 'Validated redeems from Bob'

  # Got an active channel!
  { a_channel, b_channel }

# Create trade request as Alice to sell some random amount of BTC/BTC-TEST
rand_trade = ({ a_channel, b_channel }) ->
  selling = [ 'BTC', 'BTC-TEST' ][0|Math.random()*2]
  buying = { BTC: 'BTC-TEST', 'BTC-TEST': 'BTC' }[selling]
  sell_amount = 0 | Math.random()*(a_channel.balances[selling][a_key.shortid]/2)
  buy_amount = 0 | sell_amount * exchange_rates[selling]

  debug_alice 'Selling %d %s to Bob for %d %s', sell_amount, selling, buy_amount, buying

  a_changes = {}
  a_changes[selling] = sell_amount * -1
  a_changes[buying] = buy_amount

  # 1. Alice: Create signed trade request
  a_trade_signed = a_channel.create_trade_req a_changes
  debug_alice 'Trade changes: %j', a_changes
  debug_alice 'Trade new balances:%j', a_trade_signed.trade.balances
  # Alice: a_trade_signed -> Arbitrator over network...

  debug 'Alice trade #%d: %s', a_trade_signed.trade.seq, pj a_changes

  # 2. Arbitrator: Verify Alice sig, send unsigned trade request to Bob
  unless a_key.verify_message (JSON.stringify a_trade_signed.trade), a_trade_signed.sig
    throw new Error 'Invalid trade signature'
  debug_arb 'Alice signature valid, sending unsigned to Bob'
  a_trade = a_trade_signed.trade
  # Arbitrator: a_trade -> Bob over network... (no sig)

  # 3. Bob: Parse request, verify, sign
  b_changes = b_channel.parse_trade a_trade
  debug_bob 'Trade changes: %j', b_changes
  # Assume Bob agrees...
  b_trade_sig = b_channel.sign_trade a_trade
  # Bob: b_trade_sig -> Arbitrator over network...

  # 4. Arbitrator: Verify Bob trade/sig, sign and send to Bob & Alice
  unless b_key.verify_message (JSON.stringify a_trade_signed.trade), b_trade_sig
    throw new Error 'Invalid trade signature'
  debug_arb 'Bob signature valid, sending final trade to Bob & Alice'

  sigs = {}
  sigs[a_key.shortid] = a_trade_signed.sig
  sigs[b_key.shortid] = b_trade_sig
  sigs[arb_key.shortid] = arb_key.sign_message JSON.stringify a_trade_signed.trade

  final_trade = trade: a_trade_signed.trade, sigs: sigs
  # Arbitrator: final_trade -> Bob,Alice over network...

  # 5. Update states as Bob & Alice
  a_channel.update final_trade
  b_channel.update final_trade
  debug 'Trade completed, new balances: %s', pj a_channel.balances

consolidate = ->
  # 1. Alice: create and sign finalize txs
  txs = a_channel.create_finalize_txs()
  for currency, tx of txs
    buff = new Buffer tx.serialize()
    debug 'Fianalize tx %s: %s', currency, buff.toString('hex')
  # Alice: txs, channel.balances, channel.sigs -> Arbitrator over network...

  # 2. Arbitrator: validate trade sigs and sign tx
  # @TODO validate trade sigs

  for asset, tx of txs
    sign_multisig arb_key, tx, a_channel.multisig_script()

  # 3. Arbitrator: broadcast to network
  debug 'Broadcasting...'
  for asset, tx of txs then do (asset, tx) ->
    debug_alice 'Broadcasting to %s network', asset
    pushtx asset, tx, (err, txid) ->
      if err? then console.error err
      else debug 'Broadcasted to %s: %s', asset, txid

rl = readline.createInterface input: process.stdin, output: process.stdout


{ a_channel, b_channel } = create_channel()

debug 'Payment channel ready.'
debug 'Expires: %s', new Date a_channel.expires
for asset in [ 'BTC', 'BTC-TEST' ]
  debug '%s address: %s', asset, a_channel.multisig_address asset
debug ''

debug 'Awaiting payment txs to be sent:'
for user, [ funding, channel ] of { Alice: [ a_funding, a_channel ], Bob: [ b_funding, b_channel ] }
  for asset, output of funding
    cap = format_satoshis channel.my_assets[asset].cap
    multisig = a_channel.multisig_address asset
    debug '%s: send %s %s to %s (expecting output %s:%d)', user, cap, asset, multisig, output.txid, output.index

rl.question 'Press ENTER once the transactions are made', ->
  debug 'Current balances: %s', pj a_channel.balances

  rl.question 'Press ENTER to start trades', ->
    start = +Date.now()
    for i in [1..num_trades]
      rand_trade { a_channel, b_channel }
    time = (Date.now() - start)/1000
    tps = num_trades/time
    #debug 'Done! %d trades were executed in %ds time, for a total of %d TPS', num_trades, time, tps
    #return rl.close()
    do ask = -> rl.question 'You have decided to close the trading channel. Do you agree to sign the transactions? (Y/n) ', (answer) ->
      return do ask unless answer.toLowerCase() is 'y'
      do consolidate
      rl.close()
