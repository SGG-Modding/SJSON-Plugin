---@meta _
---@diagnostic disable

-- global dependencies:
local pairs, type, tostring, tonumber, getmetatable, setmetatable =
      pairs, type, tostring, tonumber, getmetatable, setmetatable
local error, require, pcall, select = error, require, pcall, select
local floor, huge = math.floor, math.huge
local strrep, gsub, strsub, strbyte, strchar, strfind, strformat =
      string.rep, string.gsub, string.sub, string.byte, string.char,
      string.find, string.format
local strmatch = string.match
local concat = table.concat
local insert = table.insert

local sjson = { }

local _ENV = nil -- blocking globals in Lua 5.2

sjson.null = setmetatable ({}, {
  __tosjson = function () return "null" end
})

local function isarray (tbl)
  local max, n, arraylen = 0, 0, 0
  for k,v in pairs (tbl) do
    if k == 'n' and type(v) == 'number' then
      arraylen = v
      if v > max then
        max = v
      end
    else
      if type(k) ~= 'number' or k < 1 or floor(k) ~= k then
        return false
      end
      if k > max then
        max = k
      end
      n = n + 1
    end
  end
  if max > 10 and max > arraylen and max > n * 2 then
    return false -- don't create an array with too many holes
  end
  return true, max
end

local escapecodes = {
  ["\""] = "\\\"", ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n",  ["\r"] = "\\r",  ["\t"] = "\\t"
}

local function escapeutf8 (uchar)
  local value = escapecodes[uchar]
  if value then
    return value
  end
  local a, b, c, d = strbyte (uchar, 1, 4)
  a, b, c, d = a or 0, b or 0, c or 0, d or 0
  if a <= 0x7f then
    value = a
  elseif 0xc0 <= a and a <= 0xdf and b >= 0x80 then
    value = (a - 0xc0) * 0x40 + b - 0x80
  elseif 0xe0 <= a and a <= 0xef and b >= 0x80 and c >= 0x80 then
    value = ((a - 0xe0) * 0x40 + b - 0x80) * 0x40 + c - 0x80
  elseif 0xf0 <= a and a <= 0xf7 and b >= 0x80 and c >= 0x80 and d >= 0x80 then
    value = (((a - 0xf0) * 0x40 + b - 0x80) * 0x40 + c - 0x80) * 0x40 + d - 0x80
  else
    return ""
  end
  if value <= 0xffff then
    return strformat ("\\u%.4x", value)
  elseif value <= 0x10ffff then
    -- encode as UTF-16 surrogate pair
    value = value - 0x10000
    local highsur, lowsur = 0xD800 + floor (value/0x400), 0xDC00 + (value % 0x400)
    return strformat ("\\u%.4x\\u%.4x", highsur, lowsur)
  else
    return ""
  end
end

local function fsub (str, pattern, repl)
  -- gsub always builds a new string in a buffer, even when no match
  -- exists. First using find should be more efficient when most strings
  -- don't contain the pattern.
  if strfind (str, pattern) then
    return gsub (str, pattern, repl)
  else
    return str
  end
end

local function quotestring (value,is_key,state)
  --[[
  -- based on the regexp "escapable" in https://github.com/douglascrockford/JSON-js
  value = fsub (value, "[%z\1-\31\"\\\127]", escapeutf8)
  if strfind (value, "[\194\216\220\225\226\239]") then
    value = fsub (value, "\194[\128-\159\173]", escapeutf8)
    value = fsub (value, "\216[\128-\132]", escapeutf8)
    value = fsub (value, "\220\143", escapeutf8)
    value = fsub (value, "\225\158[\180\181]", escapeutf8)
    value = fsub (value, "\226\128[\140-\143\168-\175]", escapeutf8)
    value = fsub (value, "\226\129[\160-\175]", escapeutf8)
    value = fsub (value, "\239\187\191", escapeutf8)
    value = fsub (value, "\239\191[\176-\191]", escapeutf8)
  end
  --]] -- bad hack
  if is_key ~= false then
	if is_key == true and type(value) == 'string' and value:match('^[a-zA-Z0-9-_]+$') then
		return value
	end
  elseif value:find('\n') then
	-- TOOD: handle indent here
	local level = (state.level or 1) - 1
	local total = '"""'
	local i = 0
	local n = select(2, value:gsub('\n', ''))
	-- https://gist.github.com/iwanbk/5479582
	for line in value:gmatch("([^\n]*)\n?") do
	  if i > 0 and i <= n then
		total = total .. '\n' .. strrep ("  ", level)
	  end
	  total = total .. line
	  i = i + 1
	end
	total = total .. '"""'
	return total
  elseif value:find('"') then
	return '"""' .. value .. '"""'
  end
  return '"' .. value .. '"'
end
sjson.quotestring = quotestring

local function replace(str, o, n)
  local i, j = strfind (str, o, 1, true)
  if i then
    return strsub(str, 1, i-1) .. n .. strsub(str, j+1, -1)
  else
    return str
  end
end

-- locale independent num2str and str2num functions
local decpoint, numfilter

local function updatedecpoint ()
  decpoint = strmatch(tostring(0.5), "([^05+])")
  -- build a filter that can be used to remove group separators
  numfilter = "[^0-9%-%+eE" .. gsub(decpoint, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "]+"
end

updatedecpoint()

local function num2str (num)
  return replace(fsub(tostring(num), numfilter, ""), decpoint, ".")
end

local function str2num (str)
  local num = tonumber(replace(str, ".", decpoint))
  if not num then
    updatedecpoint()
    num = tonumber(replace(str, ".", decpoint))
  end
  return num
end

local function addnewline2 (level, buffer, buflen)
  buffer[buflen+1] = "\n"
  buffer[buflen+2] = strrep ("  ", level)
  buflen = buflen + 2
  return buflen
end

function sjson.addnewline (state)
  if state.indent then
    state.bufferlen = addnewline2 (state.level or 0,
                           state.buffer, state.bufferlen or #(state.buffer))
  end
end

local encode2 -- forward declaration

local function addpair (key, value, prev, indent, level, buffer, buflen, tables, globalorder, pretty, state)
  local kt = type (key)
  if kt ~= 'string' and kt ~= 'number' then
    return nil, "type '" .. kt .. "' is not supported as a key by SJSON."
  end
  if prev then
    buflen = buflen + 1
    buffer[buflen] = pretty and '' or ','
  end
  if indent or pretty then
    buflen = addnewline2 (level, buffer, buflen)
  end
  buffer[buflen+1] = quotestring (key,true,state)
  buffer[buflen+2] = pretty and " = " or "="
  return encode2 (value, indent, level, buffer, buflen + 2, tables, globalorder, pretty, state)
end

local function appendcustom(res, buffer, state)
  local buflen = state.bufferlen
  if type (res) == 'string' then
    buflen = buflen + 1
    buffer[buflen] = res
  end
  return buflen
end

local function exception(reason, value, state, buffer, buflen, defaultmessage)
  defaultmessage = defaultmessage or reason
  local handler = state.exception
  if not handler then
    return nil, defaultmessage
  else
    state.bufferlen = buflen
    local ret, msg = handler (reason, value, state, defaultmessage)
    if not ret then return nil, msg or defaultmessage end
    return appendcustom(ret, buffer, state)
  end
end

function sjson.encodeexception(reason, value, state, defaultmessage)
  return quotestring("<" .. defaultmessage .. ">")
end

encode2 = function (value, indent, level, buffer, buflen, tables, globalorder, pretty, state)
  local valtype = type (value)
  local valmeta = getmetatable (value)
  valmeta = type (valmeta) == 'table' and valmeta -- only tables
  local valtosjson = valmeta and valmeta.__tosjson
  if valtosjson then
    if tables[value] then
      return exception('reference cycle', value, state, buffer, buflen)
    end
    tables[value] = true
    state.bufferlen = buflen
    local ret, msg = valtosjson (value, state)
    if not ret then return exception('custom encoder failed', value, state, buffer, buflen, msg) end
    tables[value] = nil
    buflen = appendcustom(ret, buffer, state)
  elseif value == nil then
    buflen = buflen + 1
    buffer[buflen] = "null"
  elseif valtype == 'number' then
    local s
    if value ~= value or value >= huge or -value >= huge then
      -- This is the behaviour of the original JSON implementation.
      s = "null"
    else
      s = num2str (value)
    end
    buflen = buflen + 1
    buffer[buflen] = s
  elseif valtype == 'boolean' then
    buflen = buflen + 1
    buffer[buflen] = value and "true" or "false"
  elseif valtype == 'string' then
    buflen = buflen + 1
    buffer[buflen] = quotestring (value,false,state)
  elseif valtype == 'table' then
    if tables[value] then
      return exception('reference cycle', value, state, buffer, buflen)
    end
    tables[value] = true
    level = level + 1
    local isa, n = isarray (value)
    if n == 0 and valmeta and valmeta.__sjsontype == 'object' then
      isa = false
    end
    local msg
    if isa then -- JSON array
	  if pretty then
		buflen = addnewline2 (level, buffer, buflen)
	  end
      buflen = buflen + 1
      buffer[buflen] = "["
	  if pretty then
		level = level + 1
		buflen = addnewline2 (level, buffer, buflen)
	  end
      for i = 1, n do
        buflen, msg = encode2 (value[i], indent, level, buffer, buflen, tables, globalorder, pretty, state)
        if not buflen then return nil, msg end
        if i < n then
          buflen = buflen + 1
          buffer[buflen] = pretty and '' or ','
		  if pretty then
			buflen = addnewline2 (level, buffer, buflen)
		  end
        end

      end
	  if pretty then
		level = level - 1
		buflen = addnewline2 (level, buffer, buflen)
	  end
      buflen = buflen + 1
      buffer[buflen] = "]"
    else -- JSON object
      local prev = false
      buflen = buflen + 1
      buffer[buflen] = "{"
      local order = valmeta and valmeta.__sjsonorder or globalorder
      if order then
        local used = {}
        n = #order
        for i = 1, n do
          local k = order[i]
          local v = value[k]
          if v then
            used[k] = true
            buflen, msg = addpair (k, v, prev, indent, level, buffer, buflen, tables, globalorder, pretty, state)
            prev = true -- add a seperator before the next element
          end
        end
        for k,v in pairs (value) do
          if not used[k] then
            buflen, msg = addpair (k, v, prev, indent, level, buffer, buflen, tables, globalorder, pretty, state)
            if not buflen then return nil, msg end
            prev = true -- add a seperator before the next element
          end
        end
      else -- unordered
        for k,v in pairs (value) do
          buflen, msg = addpair (k, v, prev, indent, level, buffer, buflen, tables, globalorder, pretty, state)
          if not buflen then return nil, msg end
          prev = true -- add a seperator before the next element
        end
      end
      if indent or pretty then
        buflen = addnewline2 (level - 1, buffer, buflen)
      end
      buflen = buflen + 1
      buffer[buflen] = "}"
    end
    tables[value] = nil
  else
    return exception ('unsupported type', value, state, buffer, buflen,
      "type '" .. valtype .. "' is not supported by JSON.")
  end
  return buflen
end

function sjson.encode (value, state)
  state = state or {}
  local oldbuffer = state.buffer
  local buffer = oldbuffer or {}
  state.buffer = buffer
  updatedecpoint()
  local ret, msg = encode2 (value, state.indent, state.level or 0,
                   buffer, state.bufferlen or 0, state.tables or {}, state.keyorder, state.pretty, state)
  if not ret then
    error (msg, 2)
  elseif oldbuffer == buffer then
    state.bufferlen = ret
    return true
  else
    state.bufferlen = nil
    state.buffer = nil
    return concat (buffer)
  end
end

local function loc (str, where)
  local line, pos, linepos = 1, 1, 0
  while true do
    pos = strfind (str, "\n", pos, true)
    if pos and pos < where then
      line = line + 1
      linepos = pos
      pos = pos + 1
    else
      break
    end
  end
  return "line " .. line .. ", column " .. (where - linepos)
end

local escapechars = {
  ["\""] = "\"", ["\\"] = "\\", ["/"] = "/", ["b"] = "\b", ["f"] = "\f",
  ["n"] = "\n", ["r"] = "\r", ["t"] = "\t"
}

local function unichar (value)
  if value < 0 then
    return nil
  elseif value <= 0x007f then
    return strchar (value)
  elseif value <= 0x07ff then
    return strchar (0xc0 + floor(value/0x40),
                    0x80 + (floor(value) % 0x40))
  elseif value <= 0xffff then
    return strchar (0xe0 + floor(value/0x1000),
                    0x80 + (floor(value/0x40) % 0x40),
                    0x80 + (floor(value) % 0x40))
  elseif value <= 0x10ffff then
    return strchar (0xf0 + floor(value/0x40000),
                    0x80 + (floor(value/0x1000) % 0x40),
                    0x80 + (floor(value/0x40) % 0x40),
                    0x80 + (floor(value) % 0x40))
  else
    return nil
  end
end

local function optionalmetatables(...)
	if select("#", ...) > 0 then
		return ...
	else
		return {__sjsontype = 'object'}, {__sjsontype = 'array'}
	end
end

local g = require ("lpeg")

local pegmatch = g.match
local P, S, R = g.P, g.S, g.R

local function ErrorCall (str, pos, msg, state)
	if not state.msg then
		state.msg = msg .. " at " .. loc (str, pos)
		state.pos = pos
	end
	return false
end

local function Err (msg)
	return g.Cmt (g.Cc (msg) * g.Carg (2), ErrorCall)
end

local BasicComment = P"//" * (1 - S"\n\r")^0
local MultiLineComment = P"/*" * (1 - P"*/")^0 * P"*/"
local Space = (S" \n\r\t" + P"\239\187\191" + BasicComment + MultiLineComment)^0

local PlainChar = 1 - S"\"\\\n\r"
local SGGEscape = R("09","AZ","az") + S"_-[]" -- bad hack
local EscapeSequence = P"\\" * g.C ((S"\"\\/bfnrt") / escapechars + SGGEscape)
local HexDigit = R("09", "af", "AF")
local function UTF16Surrogate (match, pos, high, low)
	high, low = tonumber (high, 16), tonumber (low, 16)
	if 0xD800 <= high and high <= 0xDBff and 0xDC00 <= low and low <= 0xDFFF then
		return true, unichar ((high - 0xD800)  * 0x400 + (low - 0xDC00) + 0x10000)
	else
		return false
	end
end
local function UTF16BMP (hex)
	return unichar (tonumber (hex, 16))
end
local U16Sequence = (P"\\u" * g.C (HexDigit * HexDigit * HexDigit * HexDigit))
local UnicodeEscape = g.Cmt (U16Sequence * U16Sequence, UTF16Surrogate) + U16Sequence/UTF16BMP
local Char = UnicodeEscape + EscapeSequence + PlainChar
local String = P'"' * g.Cs (Char ^ 0) * (P'"' + Err "unterminated string")
local BasicStringChar = S" \n\r\t" + P"\239\187\191" + Char
--local ComplexStringChar = (BasicStringChar * BasicStringChar^-1) + g.Cg(P'"""','end') + (P'"' * P'"'^-1)
local BasicString = P'"' * g.Cs (BasicStringChar ^ 0) * (P'"' + Err "unterminated string")
local ComplexString --= P'"""' * g.Cs (BasicStringChar ^ 0) * (P'"""' + Err "unterminated multiline string")
do -- https://www.gammon.com.au/scripts/doc.php?lua=lpeg.Cmt
	local equals = g.P'"'
	local open = '"' * g.Cg(equals, "init") * '"'
	local close = '"' * g.C(equals) * '"'
	local closeeq = g.Cmt(close * g.Cb("init"), function (s, i, a, b) return a == b end)
	local string = open * g.C((g.P(1) - closeeq)^0) * close / 1
	ComplexString = string
end

local Integer = P"-"^(-1) * (P"0" + (R"19" * R"09"^0))
local Fractal = P"." * R"09"^0
local Exponent = (S"eE") * (S"+-")^(-1) * R"09"^1
local Number = (Integer * Fractal^(-1) * Exponent^(-1))/str2num
local Constant = P"true" * g.Cc (true) + P"false" * g.Cc (false) + P"null" * g.Carg (1)
local SimpleValue = Number + ComplexString + BasicString + Constant
local ArrayContent, ObjectContent

-- The functions parsearray and parseobject parse only a single value/pair
-- at a time and store them directly to avoid hitting the LPeg limits.
local function parsearray (str, pos, nullval, state)
	local obj, cont
	local npos
	local t, nt = {}, 0
	repeat
		obj, cont, npos = pegmatch (ArrayContent, str, pos, nullval, state)
		if not npos then break end
		pos = npos
		nt = nt + 1
		t[nt] = obj
	until cont == 'last'
	return pos, setmetatable (t, state.arraymeta)
end

local function parseobject (str, pos, nullval, state)
	local obj, key, cont
	local npos
	local o = {}
	local t = {}
	repeat
		key, obj, cont, npos = pegmatch (ObjectContent, str, pos, nullval, state)
		if not npos then break end
		pos = npos
		insert(o,key)
		t[key] = obj
	until cont == 'last'
	local meta = state.objectmeta
	if meta and meta.__sjsonorder == nil then
		meta = {}
		for k,v in pairs(state.objectmeta) do
			meta[k] = v
		end
		meta.__sjsonorder = o
	end
	return pos, setmetatable (t, meta)
end

local Array = P"[" * g.Cmt (g.Carg(1) * g.Carg(2), parsearray) * Space * (P"]" + Err "']' expected")
local Object = P"{" * g.Cmt (g.Carg(1) * g.Carg(2), parseobject) * Space * (P"}" + Err "'}' expected")
local Value = Space * (Array + Object + SimpleValue)
local ExpectedValue = Value + Space * Err "value expected"
local ValueDelimiter = P"," + P""
local KeyChar = R("09","AZ","az") + S'_-'
local Key = Space * g.Cs(String + g.Cs(KeyChar^1)) * Space
ArrayContent = Value * Space * (ValueDelimiter * g.Cc'cont' + g.Cc'last') * g.Cp()
local Pair = g.Cg (Key * (P"=" + Err "equals expected") * ExpectedValue)
ObjectContent = Pair * Space * (ValueDelimiter * g.Cc'cont' + g.Cc'last') * g.Cp()
local DecodeValue = ExpectedValue * g.Cp ()

function sjson.decode (str, pos, ...)
	local state = {}
	local nullval = sjson.null
	state.objectmeta, state.arraymeta = optionalmetatables(...)
	local obj, retpos = pegmatch (DecodeValue, str, pos, nullval, state)
	if state.msg then
		return nil, state.pos, state.msg
	else
		return obj, retpos
	end
end

function sjson.is_array(value)
	local valtype = type (value)
	if valtype ~= 'table' then return false end
	local valmeta = getmetatable (value)
    local isa, n = isarray (value)
    if n == 0 and valmeta and valmeta.__sjsontype == 'object' then
      isa = false
    end
	return isa
end

return sjson

