BigInteger = require 'bigi'
{ ECPointFp  } = require 'ecurve'
conv = require 'binstring'
lazy = require 'lazy-prop'
addr = require './addr'
{ ecparams, ecdsa } = require './ec.coffee'
{ PUBKEY_LEN, PUBKEY_C_LEN } = require './const'
{ to_ba } = require './util'
#Message = require('crypto-signmsg')(null, ecparams)

class Key
  constructor: (@type, buff, @compressed) ->
    @[@type] = buff

    # If compressed is not defined, determine it according to the public key
    # length or default to true when a private key is provided
    @compressed ?= if type is 'pub' then (buff.length is PUBKEY_C_LEN) else true

    # @TODO support private key with compressed flag and detect it here?
    # @TODO default should be uncompressed

    if type is 'priv'
      lazy this, pub: -> new Buffer ecparams.getG().multiply(@priv_bigi).getEncoded(@compressed)
    else
      lazy this, priv: -> throw new Error 'Unknown private key'

  lazy @::,
    # Private key as BigInteger
    priv_bigi: -> BigInteger.fromByteArrayUnsigned @priv_ba

    # Private key as byte array
    priv_ba: -> [ @priv... ]

    # Public key as byte array
    pub_ba: -> [ @pub... ]

    # Public key point
    pub_point: -> ECPointFp.decodeFrom ecparams.getCurve(), @pub_ba

    # Public key hex
    shortid: -> (sha256 @pub)[0..5].toString 'hex'

  # Sign raw
  sign: (data) -> new Buffer ecdsa.sign (to_ba data), @priv_bigi

  # Verify raw
  verify: (data, sig) -> ecdsa.verify (to_ba data), (to_ba sig), @pub_ba

  # @FIXME Temporary place holder until real message signing is implemented
  { sha256 } = require 'crypto-hashing'
  sign_message: (msg) -> @sign sha256 msg
  verify_message: (msg, sig) -> @verify (sha256 msg), sig

  # Returns a new Key instance from public key hex string or buffer
  @from_pub: (pub) ->
    throw new Error 'Empty public key' unless pub?.length
    pub = conv pub, in: 'hex' if typeof pub is 'string'
    throw new Error 'Invalid public key' unless pub.length in [ PUBKEY_LEN, PUBKEY_C_LEN ]
    new Key 'pub', pub

  # Returns a new Key instance from private key in base58 encoding or buffer
  @from_priv: (priv, network) ->
    if typeof priv is 'string'
      priv = addr.decode network, 'private', priv
    new Key 'priv', priv

module.exports = Key
