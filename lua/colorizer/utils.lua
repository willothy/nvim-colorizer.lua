---Helper utils
--@module utils
local bit, ffi = require "bit", require "ffi"
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

-- -- TODO use rgb as the return value from the matcher functions
-- -- instead of the rgb_hex. Can be the highlight key as well
-- -- when you shift it left 8 bits. Use the lower 8 bits for
-- -- indicating which highlight mode to use.
-- ffi.cdef [[
-- typedef struct { uint8_t r, g, b; } colorizer_rgb;
-- ]]
-- local rgb_t = ffi.typeof 'colorizer_rgb'

-- Create a lookup table where the bottom 4 bits are used to indicate the
-- category and the top 4 bits are the hex value of the ASCII byte.
local BYTE_CATEGORY = ffi.new "uint8_t[256]"
local CATEGORY_DIGIT = lshift(1, 0)
local CATEGORY_ALPHA = lshift(1, 1)
local CATEGORY_HEX = lshift(1, 2)
local CATEGORY_ALPHANUM = bor(CATEGORY_ALPHA, CATEGORY_DIGIT)

-- do not run the loop multiple times
local b = string.byte
for i = 0, 255 do
  local v = 0
  -- Digit is bit 1
  if i >= b "0" and i <= b "9" then
    v = bor(v, lshift(1, 0))
    v = bor(v, lshift(1, 2))
    v = bor(v, lshift(i - b "0", 4))
  end
  local lowercase = bor(i, 0x20)
  -- Alpha is bit 2
  if lowercase >= b "a" and lowercase <= b "z" then
    v = bor(v, lshift(1, 1))
    if lowercase <= b "f" then
      v = bor(v, lshift(1, 2))
      v = bor(v, lshift(lowercase - b "a" + 10, 4))
    end
  end
  BYTE_CATEGORY[i] = v
end

---Obvious.
---@param byte number
---@return boolean
local function byte_is_alphanumeric(byte)
  local category = BYTE_CATEGORY[byte]
  return band(category, CATEGORY_ALPHANUM) ~= 0
end

---Obvious.
---@param byte number
---@return boolean
local function byte_is_hex(byte)
  return band(BYTE_CATEGORY[byte], CATEGORY_HEX) ~= 0
end

---Merge two tables.
--
-- todo: Remove this and use `vim.tbl_deep_extend`
---@return table
local function merge(...)
  local res = {}
  for i = 1, select("#", ...) do
    local o = select(i, ...)
    if type(o) ~= "table" then
      return {}
    end
    for k, v in pairs(o) do
      res[k] = v
    end
  end
  return res
end

--- Obvious.
---@param byte number
---@return number
local function parse_hex(byte)
  return rshift(BYTE_CATEGORY[byte], 4)
end

--- Obvious.
---@param v string
---@return number|nil
local function percent_or_hex(v)
  if v:sub(-1, -1) == "%" then
    return tonumber(v:sub(1, -2)) / 100 * 255
  end
  local x = tonumber(v)
  if x > 255 then
    return
  end
  return x
end

--- @export
return {
  byte_is_alphanumeric = byte_is_alphanumeric,
  byte_is_hex = byte_is_hex,
  merge = merge,
  parse_hex = parse_hex,
  percent_or_hex = percent_or_hex,
}
