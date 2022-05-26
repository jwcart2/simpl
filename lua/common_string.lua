local common_string = {}

------------------------------------------------------------------------------
local string_rep = string.rep
local string_find = string.find
local string_sub = string.sub
local math_floor = math.floor

------------------------------------------------------------------------------
local function split_string(str, char, keep)
   local buf = {}
   if not str then
	  -- Do nothing
   elseif not string_find(str, char) then
	  buf[#buf+1] = str
   else
	  local len = #str
	  local p = 1
	  local s,e
	  repeat
		 s,e = string_find(str, char, p)
		 if e then
			if s > p then
			   buf[#buf+1] = string_sub(str, p, s-1)
			end
			if keep then
			   buf[#buf+1] = char
			end
			p = e+1
		 end
	  until not e or p > len
	  if p < len then
		 local last_str = string_sub(str, p, -1)
		 if last_str ~= "" then
			buf[#buf+1] = last_str
		 end
	  end
   end
   return buf
end
common_string.split_string = split_string

local function wrap_string(str, max)
   local buf = {}
   if not str then
	  -- Do nothing
   elseif #str <= max then
	  buf[#buf+1] = str
   else
	  local orig_pad = ""
	  local orig_str = str
	  local s,e = string_find(orig_str, "^%s+")
	  if e then
		 orig_pad = string_sub(orig_str, s, e)
		 str = string_sub(orig_str, e+1, -1)
		 max = max - #orig_pad
	  end
	  local s,e = string_find(str,"%S%s")
	  local pad = e and string_rep(" ",e) or ""
	  if e and e > max/5 then
		 pad = string.rep(" ",math_floor(max/5))
	  end
	  while str and #str > max do
		 s,e = string_find(str,"%s+")
		 local last_s,last_e = s,e
		 while e and e < max do
			last_s,last_e = s,e
			s,e = string_find(str,"%s+",e+1)
		 end
		 if not last_s then
			-- No spaces found
			buf[#buf+1] = orig_pad..str
			str = ""
		 elseif s and e and e >= max and s <= max then
			-- whitespace stradles the max
			buf[#buf+1] = orig_pad..string_sub(str,1,s-1)
			str = pad..string_sub(str,e+1)
		 elseif last_s == 1 then
			-- No spaces found after the pad and before max
			if not s then
			   -- no whitspace found
			   s = #str+1
			   e = #str+1
			   pad = ""
			end
			extra = s-1-max
			if extra > last_e then
			   extra = last_e
			end
			buf[#buf+1] = orig_pad..string_sub(str,extra+1,s-1)
			str = pad..string_sub(str,e+1)
		 else
			buf[#buf+1] = orig_pad..string_sub(str,1,last_s-1)
			str = pad..string_sub(str,last_e+1)
		 end
	  end
	  if str and str ~= "" then
		 buf[#buf+1] = orig_pad..str
	  end
   end
   return buf
end
common_string.wrap_string = wrap_string

------------------------------------------------------------------------------
return common_string
