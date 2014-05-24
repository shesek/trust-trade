# Generic handling for signing multi-signature transactions
#
# ASSUMPTIONS:
# - All inputs are from the multisig, does not work when combined with others
# - All signatures are using the same hash_type, SIGHASH_ALL by default

Script = require 'btc-script'
{ map: { OP_0 } } = require 'btc-opcode'
Key = require './key'
SIGHASH_ALL = 1

# Sign `tx` with `key`, where all inputs are to be redeemed with `redeem_script`,
# keeping previous signatures in place and in correct order
sign_multisig = (key, tx, redeem_script, hash_type = SIGHASH_ALL) ->
  pubkeys = redeem_script.extractPubkeys().map (pubkey) -> new Buffer pubkey
  hpubkeys = pubkeys.map (pubkey) -> pubkey.toString 'hex'

  throw new Error 'Invalid key' unless key.pub.toString('hex') in hpubkeys

  sign_input = (inv, i) ->
    sighash = tx.hashTransactionForSignature redeem_script, i, hash_type
    sigs = get_prev_sigs pubkeys, inv.script, sighash
    sigs[key.pub.toString 'hex'] = key.sign sighash

    in_script = new Script
    in_script.writeOp OP_0
    # Make sure signatures are in the same order as their pubkeys
    for pubkey_hex in hpubkeys when sigs[pubkey_hex]?
      in_script.writeBytes [ sigs[pubkey_hex]..., hash_type ]
    in_script.writeBytes redeem_script.buffer

    in_script

  for inv, i in tx.ins
    inv.script = sign_input inv, i
  tx

# Get the previous signatures, on an object map with the signing public key as the hash key
get_prev_sigs = (pubkeys, script, sighash) ->
  return [] unless script.chunks.length
  unless script.chunks[0] is OP_0 and script.chunks.length >= 2
    throw new Error 'Invalid script'

  sigs = {}
  for sig in script.chunks[1...-1]
    unless signer = get_signer pubkeys, sig, sighash
      throw new Error 'Invalid signature'
    # Strip out sig hash type, added back later
    sigs[signer.toString 'hex'] = sig[...-1]
  sigs

# Get the signing public key that created `sig` over `sighash`
get_signer = (pubkeys, sig, sighash) ->
  for pubkey in pubkeys when Key.from_pub(pubkey).verify sighash, sig[...-1]
    return pubkey
  return

module.exports = sign_multisig
