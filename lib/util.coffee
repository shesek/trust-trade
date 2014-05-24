# Number of satoshis in a coin
COIN_SATOSHIS = 100000000

# Pretty-format satoshis amount in whole coins
format_satoshis = (val) ->
  coins = val / COIN_SATOSHIS
  # at least two decimal places and avoid scientific notation
  if (0|coins*10) is coins*10 then coins.toFixed(2)
  else coins.toFixed(8).replace(/0+$/,'')

# Turn whole coins amounts to satoshis, throw for invalid amounts
to_satoshis = (val) ->
  val = +val
  throw new Error 'Amount must be numeric and positive' unless val is val and val >= 0
  satoshis = val * COIN_SATOSHIS
  throw new Error 'Amount cannot have more than 8 decimal places' unless satoshis%1 is 0
  '' + satoshis

# Return `val` as ByteArray. Accepts Buffers and byte arrays.
to_ba = (val) ->
  if Buffer.isBuffer val then [ val... ]
  else if Array.isArray val then val
  else throw new Error 'Unknown data type, cannot convert to byte array'

# Compare buffers
buff_eq = (a, b) -> a.toString('base64') is b.toString('base64')

# Pretty JSON
pj = (obj) -> JSON.stringify(obj, null, 2).replace /\n/g, '\n  '

module.exports = { format_satoshis, to_satoshis, to_ba, buff_eq, pj }
