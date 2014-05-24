btcd = require 'btcd'

servers =
  BTC: process.env.BTCD_SERVER
  'BTC-TEST': process.env.BTCD_TEST_SERVER
cert = process.env.BTCD_CERT

connections = {}

pushtx = (asset, tx, cb) ->
  rawtx = new Buffer(tx.serialize()).toString('hex')
  (connections[asset] ?= btcd servers[asset], cert)
    .sendrawtransaction rawtx, cb

module.exports = pushtx
