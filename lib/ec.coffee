ECDSA = require 'ecdsa'
ecparams = require('ecurve-names')('secp256k1')

ecdsa = new ECDSA ecparams

module.exports = {
  ecparams, ecdsa
}
