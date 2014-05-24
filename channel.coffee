Script = require 'btc-script'
Transaction = require 'btc-transaction'


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
  constructor: (@key, { @expires, @me, @other, @arbitrator }) ->
  # me.assets, other.pub, other.assets, arbitrator.pub

  make_redeems: (user_assets, funding, sign=false) ->
    redeems = {}
    redeem_script = @multisig_script() if sign
    for asset, outputs of funding
      unless asset of user_assets
        throw new Error "Invalid asset provided for redeem: #{ asset }"
      redeems[asset] = for { txid, index } in outputs
        tx = create_redeem asset, user_assets[asset], txid, index
        sign_multisig @key, tx, redeem_script if sign
        tx

  create_redeem: (asset, user_asset, txid, index) ->
    tx = new Transaction lock_time: @expires + LOCKTIME_GAP
    tx.addInput { hash: txid }, index
    tx.addOutput (to_ccAddress asset, user_asset.address), (num_to_bytes user_asset.cap)
    tx

  validate_redeems: (redeems) ->
    # @TODO
    # - Validate the redeem ntxid matches the expected one
    # - Validate sigs
    true

  multisig_script: ->
    Script.createMultiSigOutputScript 2, [ @me.pub, @other.pub, @arbitrator.pub ].sort()

  multisig_address: (asset) -> addr.encode currency, 'scripthash', @multisig_script()
