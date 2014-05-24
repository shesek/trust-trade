coinstring = require 'coinstring'
coininfo = require 'coininfo'
{ sha256ripe160 } = require 'crypto-hashing'
{ RIPEMD160_LEN, PRIVKEY_LEN, PRIVKEY_C_LEN, PRIVKEY_C_BYTE } = require './const'

# Wrapper around coinstring with some extra coin-specific 
# utilities and validation

get_versions = (network) ->
  data = (coininfo network) or throw new Error 'Invalid network'
  data.versions

# Turn a byte array to a string address
#
# Example: encode 'BTC', 'public', bytes
encode = (network, type, bytes) ->
  V = get_versions network
  version = V[type] ? throw new Error 'Invalid type'
  # Apply sha256ripemd160 on plain pubkeys/scripts
  if type in [ 'public', 'scripthash' ] and bytes.length isnt RIPEMD160_LEN
    bytes = sha256ripe160 bytes

  coinstring version, bytes

# Parse and validate base58 addresses
#
# Example: decode 'BTC', address
decode = (network, expected_type, address) ->
  V = get_versions network
  [ address, expected_type ] = [ expected_type, null ] unless address?

  { version, bytes } = coinstring.decode address

  if expected_type?
    expected_version = V[expected_type] ? throw new Error 'Unknown address type'
    unless expected_version is version
      throw new Error 'Invalid address version'

  # Ensure data format matches the version
  switch version
    when V.public, V.scripthash
      unless bytes.length is RIPEMD160_LEN
        throw new Error 'Invalid address length'
    when V.private
      unless (bytes.length is PRIVKEY_LEN) or \
             (bytes.length is PRIVKEY_C_LEN and bytes[33] is PRIVKEY_C_BYTE)
        throw new Error 'Invalid private key format'
    else
      throw new Error 'Invalid address version'
  { version, bytes }

# Validate address
#
# `types` can be an array of expected types or a single type
# Example: validate 'BTC', [ 'public', 'scripthash' ], address
validate = (network, types, address) ->
  V = get_versions network
  [ address, types ] = [ types, null ] unless address?
  try
    { version } = decode network, address
    not types or version in [].concat(types).map (t) -> V[t]
  catch err then false

# Mock cryptocoinjs's btc-address Address format
#
# Required because btc-address is Bitcoin-specific and represents
# the address network/type differently. Only mocking the functionallity
# needed for Bitrated to operate.
to_ccAddress = (network, expected_type, address) ->
  V = get_versions network
  { version, bytes } = decode network, expected_type, address

  for _type, _ver of V when _ver is version
    type = cc_types_map[_type]
    break
  
  hash: Array.apply null, bytes
  version: version
  getType: -> type

cc_types_map = public: 'pubkeyhash', scripthash: 'scripthash'

# Turn Script to an address
script_to_addr = (network, script) ->
  switch script.getOutType()
    when 'pubkey'     then encode network, 'public',     script.chunks[0]
    when 'pubkeyhash' then encode network, 'public',     script.chunks[2]
    when 'scripthash' then encode network, 'scripthash', script.chunks[1]
    else throw new Error 'Unknown address type'

module.exports = { encode, decode, validate, to_ccAddress, script_to_addr }
