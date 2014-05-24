bytes_to_num = (bytes) ->
  if bytes.length then bytes[0] + 256 * bytes_to_num bytes.slice 1
  else 0

num_to_bytes = (num, length=8) ->
  if length then [num % 256].concat num_to_bytes (0 | num / 256), length-1
  else []

module.exports = { num_to_bytes, bytes_to_num }
