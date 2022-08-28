---Helper functions to highlight buffer smartly
--@module colorizer.buffer_utils
local api = vim.api
local buf_set_virtual_text = api.nvim_buf_set_extmark
local buf_get_lines = api.nvim_buf_get_lines
local create_namespace = api.nvim_create_namespace
local clear_namespace = api.nvim_buf_clear_namespace
local set_highlight = api.nvim_set_hl

local color_utils = require "colorizer.color_utils"
local color_is_bright = color_utils.color_is_bright

local matcher_utils = require "colorizer.matcher_utils"
local make_matcher = matcher_utils.make_matcher

--- Default namespace used in `highlight_buffer` and `colorizer.attach_to_buffer`.
-- @see highlight_buffer
-- @see colorizer.attach_to_buffer
local DEFAULT_NAMESPACE = create_namespace "colorizer"
local HIGHLIGHT_NAME_PREFIX = "colorizer"
--- Highlight mode which will be use to render the colour
local HIGHLIGHT_MODE_NAMES = {
  background = "mb",
  foreground = "mf",
  virtualtext = "mv",
}
local HIGHLIGHT_CACHE = {}

--- Make a deterministic name for a highlight given these attributes
local function make_highlight_name(rgb, mode)
  return table.concat({ HIGHLIGHT_NAME_PREFIX, HIGHLIGHT_MODE_NAMES[mode], rgb }, "_")
end

local function create_highlight(rgb_hex, options)
  local mode = options.mode or "background"
  -- TODO validate rgb format?
  rgb_hex = rgb_hex:lower()
  local cache_key = table.concat({ HIGHLIGHT_MODE_NAMES[mode], rgb_hex }, "_")
  local highlight_name = HIGHLIGHT_CACHE[cache_key]

  -- Look up in our cache.
  if highlight_name then
    return highlight_name
  end

  -- convert from #fff to #ffffff
  if #rgb_hex == 3 then
    rgb_hex = table.concat {
      rgb_hex:sub(1, 1):rep(2),
      rgb_hex:sub(2, 2):rep(2),
      rgb_hex:sub(3, 3):rep(2),
    }
  end

  -- Create the highlight
  highlight_name = make_highlight_name(rgb_hex, mode)
  if mode == "foreground" then
    set_highlight(0, highlight_name, { fg = "#" .. rgb_hex })
  else
    local rr, gg, bb = rgb_hex:sub(1, 2), rgb_hex:sub(3, 4), rgb_hex:sub(5, 6)
    local r, g, b = tonumber(rr, 16), tonumber(gg, 16), tonumber(bb, 16)
    local fg_color
    if color_is_bright(r, g, b) then
      fg_color = "Black"
    else
      fg_color = "White"
    end
    set_highlight(0, highlight_name, { fg = fg_color, bg = "#" .. rgb_hex })
  end
  HIGHLIGHT_CACHE[cache_key] = highlight_name
  return highlight_name
end

local function add_highlight(options, buf, ns, data)
  if vim.tbl_contains({ "foreground", "background" }, options.mode) then
    for linenr, hls in pairs(data) do
      for _, hl in ipairs(hls) do
        api.nvim_buf_add_highlight(buf, ns, hl.name, linenr, hl.range[1], hl.range[2])
      end
    end
  elseif options.mode == "virtualtext" then
    for linenr, hls in pairs(data) do
      for _, hl in ipairs(hls) do
        buf_set_virtual_text(0, ns, linenr, hl.range[2], {
          end_col = hl.range[2],
          virt_text = { { options.virtualtext or "■", hl.name } },
        })
      end
    end
  end
end

--- Highlight the buffer region.
-- Highlight starting from `line_start` (0-indexed) for each line described by `lines` in the
-- buffer `buf` and attach it to the namespace `ns`.
---@param buf number: buffer id
---@param ns number: The namespace id. Default is DEFAULT_NAMESPACE. Create it with `vim.api.create_namespace`
---@param lines table: the lines to highlight from the buffer.
---@param line_start number: line_start should be 0-indexed
---@param options table: Configuration options as described in `setup`
local function highlight_buffer(buf, ns, lines, line_start, options)
  if buf == 0 or buf == nil then
    buf = api.nvim_get_current_buf()
  end

  ns = ns or DEFAULT_NAMESPACE
  local loop_parse_fn = make_matcher(options)
  if not loop_parse_fn then
    return false
  end

  local data = {}
  local mode = options.mode == "background" and { mode = "background" } or { mode = "foreground" }
  for current_linenum, line in ipairs(lines) do
    current_linenum = current_linenum - 1 + line_start
    -- Upvalues are options and current_linenum
    local i = 1
    while i < #line do
      local length, rgb_hex = loop_parse_fn(line, i)
      if length then
        local name = create_highlight(rgb_hex, mode)
        local d = data[current_linenum] or {}
        table.insert(d, { name = name, range = { i - 1, i + length - 1 } })
        data[current_linenum] = d
        i = i + length
      else
        i = i + 1
      end
    end
  end
  add_highlight(options, buf, ns, data)
end

local BUFFER_LINES = {}
--- Rehighlight the buffer if colorizer is active
---@param buf number: Buffer number
---@param options table: Buffer options
local function rehighlight_buffer(buf, options)
  if buf == 0 or buf == nil then
    buf = api.nvim_get_current_buf()
  end

  local ns = DEFAULT_NAMESPACE

  if not BUFFER_LINES[buf] then
    BUFFER_LINES[buf] = {}
  end

  local a = api.nvim_buf_call(buf, function()
    return {
      vim.fn.line "w0",
      vim.fn.line "w$",
    }
  end)
  local min, max
  local new_min, new_max = a[1] - 1, a[2]
  local old_min, old_max = BUFFER_LINES[buf]["min"], BUFFER_LINES[buf]["max"]

  if old_min and old_max then
    -- Triggered for TextChanged autocmds
    -- TODO: Find a way to just apply highlight to changed text lines
    if old_max == new_max then
      min, max = new_min, new_max
    -- Triggered for WinScrolled autocmd - Scroll Down
    elseif old_max < new_max then
      min = old_max
      max = new_max
    -- Triggered for WinScrolled autocmd - Scroll Up
    elseif old_max > new_max then
      min = new_min
      max = new_min + (old_max - new_max)
    end
    -- just in case a long jump was made
    if max - min > new_max - new_min then
      min = new_min
      max = new_max
    end
  end

  min = min or new_min
  max = max or new_max
  clear_namespace(buf, ns, min, max)
  local lines = buf_get_lines(buf, min, max, false)
  highlight_buffer(buf, ns, lines, min, options)
  -- store current window position to be used later to incremently highlight
  BUFFER_LINES[buf]["max"] = new_max
  BUFFER_LINES[buf]["min"] = new_min
end

--- @export
return {
  DEFAULT_NAMESPACE = DEFAULT_NAMESPACE,
  HIGHLIGHT_MODE_NAMES = HIGHLIGHT_MODE_NAMES,
  rehighlight_buffer = rehighlight_buffer,
  highlight_buffer = highlight_buffer,
}
