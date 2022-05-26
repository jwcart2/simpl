local STRING = require "common_string"

local buffer = {}

------------------------------------------------------------------------------
local string_rep = string.rep
local string_find = string.find

------------------------------------------------------------------------------
local function get_new_format(indent, width)
   return {indent=indent, width=width, depth=0, pad=""}
end
buffer.get_new_format = get_new_format

local function format_increase_depth(format)
   format.depth = format.depth + 1
   format.pad = string_rep(" ",format.indent*format.depth)
end
buffer.format_increase_depth = format_increase_depth

local function format_decrease_depth(format)
   format.depth = format.depth - 1
   if format.depth <= 0 then
	  format.depth = 0
	  format.pad = ""
   else
	  format.pad = string_rep(" ",format.indent*format.depth)
   end
end
buffer.format_decrease_depth = format_decrease_depth

local function format_get_max(format)
   local _,padlen = string_find(format.pad,"%S%s")
   padlen = padlen or 0
   return format.width - padlen
end
buffer.format_get_max = format_get_max

------------------------------------------------------------------------------

local function add_to_buffer(buf, format, str)
   if not str then
	  return
   end
   local max = format_get_max(format)
   if #str > max then
	  local buf2 = STRING.split_string(str,"\n", false)
	  for i=1,#buf2 do
		 local v = buf2[i]
		 local buf3 = STRING.wrap_string(v,max)
		 for j=1,#buf3 do
			local w = buf3[j]
			buf[#buf+1] = format.pad..w
			buf[#buf+1] = "\n"
		 end
	  end
   else
	  buf[#buf+1] = format.pad..str
	  buf[#buf+1] = "\n"
   end
end
buffer.add_to_buffer = add_to_buffer

local function convert_to_buffer(format, str)
   if not str then
	  return
   end
   local buf = {}
   add_to_buffer(buf, format, str)
   return buf
end
buffer.convert_to_buffer = convert_to_buffer

local function write(out, format, str)
   if not str then
	  return
   end
   local buf = convert_to_buffer(format, str)
   for i = 1,#buf do
	  out:write(buf[i])
   end
end
buffer.write = write

------------------------------------------------------------------------------
return buffer
