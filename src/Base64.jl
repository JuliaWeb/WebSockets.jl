char2digit(c::Char) = '0' <= c <= '9' ? c-'0' : lowercase(c)-'a'+10

hex2bytes(s::ASCIIString) =
  [ uint8(char2digit(s[i])<<4 | char2digit(s[i+1])) for i=1:2:length(s) ]

const base64chars = ['A':'Z','a':'z','0':'9','+','/']

function base64(x::Uint8, y::Uint8, z::Uint8)
  n = int(x)<<16 | int(y)<<8 | int(z)
  base64chars[(n >> 18)            + 1],
  base64chars[(n >> 12) & 0b111111 + 1],
  base64chars[(n >>  6) & 0b111111 + 1],
  base64chars[(n      ) & 0b111111 + 1]
end

function base64(x::Uint8, y::Uint8)
  a, b, c = base64(x, y, 0x0)
  a, b, c, '='
end

function base64(x::Uint8)
  a, b = base64(x, 0x0, 0x0)
  a, b, '=', '='
end

function base64(v::Array{Uint8})
  n = length(v)
  w = Array(Uint8,4*iceil(n/3))
  j = 0
  for i = 1:3:n-2
    w[j+=1], w[j+=1], w[j+=1], w[j+=1] = base64(v[i], v[i+1], v[i+2])
  end
  tail = n % 3
  if tail > 0
    w[j+=1], w[j+=1], w[j+=1], w[j+=1] = base64(v[end-tail+1:end]...)
  end
  ASCIIString(w)
end
