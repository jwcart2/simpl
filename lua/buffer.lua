local STRING = require "common_string"

local buffer = {}

------------------------------------------------------------------------------
local string_rep = string.rep

------------------------------------------------------------------------------
local function buffer_get_new_buffer(indent, width)
   local format = {indent=indent, width=width, depth=0, pad=""}
   return {format=format}
end
buffer.buffer_get_new_buffer = buffer_get_new_buffer

local function buffer_increase_depth(buf)
   local format = buf.format
   format.depth = format.depth + 1
   format.pad = string_rep(" ", format.indent*format.depth)
end
buffer.buffer_increase_depth = buffer_increase_depth

local function buffer_decrease_depth(buf)
   local format = buf.format
   format.depth = format.depth - 1
   if format.depth <= 0 then
	  format.depth = 0
	  format.pad = ""
   else
	  format.pad = string_rep(" ",format.indent*format.depth)
   end
end
buffer.buffer_decrease_depth = buffer_decrease_depth

local function buffer_add_str(buf, str)
   str = str or ""
   local lines = STRING.split_string(str, "\n", false)
   for i=1,#lines do
	  buf[#buf+1] = buf.format.pad..lines[i]
   end
end
buffer.buffer_add_str = buffer_add_str

------------------------------------------------------------------------------

local function write_line(out, max, line)
   if #line > max then
	  local strs = STRING.wrap_string(line, max)
	  for i=1,#strs do
		 out:write(strs[i], "\n")
	  end
   else
	  out:write(line, "\n")
   end
end

local function buffer_write(out, buf)
   if not out or not buf then
	  return
   end
   local format = buf.format
   for i=1,#buf do
	  write_line(out, format.width, buf[i])
   end
end
buffer.buffer_write = buffer_write

------------------------------------------------------------------------------
return buffer
