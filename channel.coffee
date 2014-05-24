Script = require 'btc-script'
{ Transaction } = require 'btc-transaction'
{ num_to_bytes } = require './lib/conv'
sign_multisig = require './lib/sign-multisig'
addr = require './lib/addr'

# Trade
# A: { balances, Asig } -> S
# S: { balances } -> B
# B: { Bsig } -> S
# S: { balances, Asig, Bsig, Ssig } -> A, B

# Finish
# X: { balances, Asig, Bsig } -> S
# S: { redeem_txs } -> X


LOCKTIME_GAP = 3600 # 1 hour


class Channel
  constructor: (@key, { @expires, @my_assets, @other_assets, @other_key, @arb_key }) ->
    @ids = {}
    @ids[@key.shortid] = @key
    @ids[@other_key.shortid] = @other_key
    @ids[@arb_key.shortid] = @arb_key

    @seq = 0
    @fundings = {}
    @balances = {}
    for asset, { cap } of @my_assets
      (@balances[asset] ||= {})[@key.shortid] = cap
    for asset, { cap } of @other_assets
      (@balances[asset] ||= {})[@other_key.shortid] = cap

  # Create redeem txs returning the `funding` outputs to the other user
  make_redeems: (user_assets, funding, sign=false) ->
    redeems = {}
    for asset, output of funding
      unless asset of user_assets
        throw new Error "Invalid asset provided for redeem: #{ asset }"
      tx = @create_redeem asset, user_assets[asset], output.txid, output.index
      sign_multisig @key, tx, @multisig_script() if sign
      redeems[asset] = tx

    redeems
    # FIXME: ensure we aren't being asked to sign our own outputs

  # Create a single (unsigned) redeem transaction
  create_redeem: (asset, user_asset, txid, index) ->
    tx = new Transaction lock_time: @expires + LOCKTIME_GAP
    tx.addInput { hash: txid }, index
    tx.addOutput (addr.to_ccAddress asset, user_asset.address), (num_to_bytes user_asset.cap)
    tx

  # Validate the redeem txs provided to us by the other party
  validate_redeems: (redeems) ->
    # @TODO
    # - Validate the redeem ntxid matches the expected one
    # - Validate sigs
    # - Keep a local copy
    true

  # Create multisig script (the same one for all assets)
  multisig_script: ->
    keys = [ @key.pub, @other_key.pub, @arb_key.pub ].map (x) -> Array.apply null, x
    @_multisig_script ||= Script.createMultiSigOutputScript 2, keys.sort()

  # Create multisig address for a specific asset
  multisig_address: (asset) ->
    @['_multisig_addr_'+asset] ||= addr.encode asset, 'scripthash', @multisig_script().buffer

  add_funding: (fundings) ->
    for asset, output of fundings
      (@fundings[asset] ?= []).push output
    return

  # Create a trade request that applies `changes` on the balances
  create_trade_req: (changes) ->
    new_balances = JSON.parse JSON.stringify @balances
    for asset, amount of changes
      new_balances[asset][@key.shortid] += amount
      new_balances[asset][@other_key.shortid] -= amount

    trade = seq: ++@seq, balances: new_balances
    { trade, sig: @sign_trade trade }

  # Parse/validate trade request and get the changes being made
  parse_trade: (trade) ->
    unless trade.seq > @seq
      throw new Error 'Invalid sequence'

    changes = {}
    for asset, balances of trade.balances
      total = 0
      for user, balance of balances
        if balance < 0 or balance%1 isnt 0
          throw new Error "Balance must be a positive integer for #{ asset }"
        total += balance
        if user is @key.shortid and balance isnt @balances[asset][user]
          changes[asset] = balance - @balances[asset][user]
      if total isnt @my_assets[asset].cap+@other_assets[asset].cap
        throw new Error "Balance for #{ asset } exceeds cap"
    changes

  # Sign trade
  sign_trade: (trade) -> @key.sign_message JSON.stringify trade

  # Validate trade sigs and update state
  update: ({ trade, sigs }) ->
    j_trade = JSON.stringify trade
    for id, key in @ids when not key.verify_message j_trade, sigs[id]
      throw new Error "Invalid signature for #{ id }"
    @seq = trade.seq
    @balances = trade.balances
    @balances_sigs = sigs

  # Create tx to finalize current balance to blockchain
  create_finalize_tx: (asset, funding, balances) ->
    tx = new Transaction
    for { txid, index } in funding
      tx.addInput { hash: txid }, index
    for id, balance of balances
      address = @get_userid_address asset, id
      unless paid_fees
        balance = balance - 1000
        paid_fees = true
      tx.addOutput (addr.to_ccAddress asset, address), (num_to_bytes balance)
    sign_multisig @key, tx, @multisig_script()
    tx

  create_finalize_txs: ->
    txs = {}
    # Assuming my_assets contains all assets
    for asset of @my_assets
      txs[asset] = @create_finalize_tx asset, @fundings[asset], @balances[asset]
    txs

  get_userid_address: (asset, id) ->
    switch id
      when @key.shortid       then @my_assets[asset].address
      when @other_key.shortid then @other_assets[asset].address
      else throw new Error 'Unknown ID'

module.exports = Channel
