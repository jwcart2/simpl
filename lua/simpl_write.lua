local LIBSIMPL = require "libsimpl"
local MSG = require "messages"
local NODE = require "node"
local TREE = require "tree"
local IFDEF = require "node_ifdef"
local BUFFER = require "buffer"
local TABLE = require "common_table"
local MACRO = require "node_macro"
local TREE = require "tree"

local simpl_write = {}

-------------------------------------------------------------------------------
local function find_common_path_from_file(node, kind, do_action, do_block, data)
   local path = NODE.get_file_name(node)
   if not path then
	  return
   end
   local dirs = {}
   local s,e,pos,len,dirname
   pos = 1
   len = #path
   if string.find(path,"^/") then
	  dirs[1] = "/"
	  pos = 2
   end
   while pos <= len do
	  s,e,dirname = string.find(path,"([^%/]+)/",pos)
	  if e then
		 dirs[#dirs+1] = dirname
		 dirs[#dirs+1] = "/"
		 pos = e + 1
	  else
		 pos = len + 1
	  end
   end
   if not data.dirs then
	  data.dirs = dirs
   else
	  local num = #data.dirs
	  local i = 1
	  while i <= num and data.dirs[i] == dirs[i] do
		 i = i + 1
	  end
	  while i <= num do
		 data.dirs[i] = nil
		 i = i + 1
	  end
   end
end

local function find_common_path(head)
   local action = {
	  ["file"] = find_common_path_from_file,
   }
   data = {}
   TREE.walk_normal_tree(head, action, data)

   local common_path
   if data.dirs then
	  common_path = table.concat(data.dirs)
   end
   return common_path
end

-------------------------------------------------------------------------------
local function compose_exp_common(exp, left, right)
   local buf = {}
   for i = 1,#exp do
	  if type(exp[i]) == "table" then
		 buf[#buf+1] = compose_exp_common(exp[i], left, right)
	  else
		 buf[#buf+1] = exp[i]
	  end
   end
   local str = table.concat(buf, " ")
   return left..str..right
end

local function compose_set(set)
   if type(set) ~= "table" then
	  if not set then
		 return "{}"
	  else
		 return tostring(set)
	  end
   elseif #set == 1 then
	  return compose_set(set[1])
   end
   return compose_exp_common(set, "{", "}")
end

local function compose_list(list)
   if type(list) ~= "table" then
	  if not list then
		 return "{}"
	  else
		 return tostring(list)
	  end
   elseif #list == 1 then
	  return compose_list(list[1])
   end
   return compose_exp_common(list, "{", "}")
end

local function compose_enclosed_list(list)
   if type(list) ~= "table" then
	  if not list then
		 return "{}"
	  else
		 return "{"..tostring(list).."}"
	  end
   end
   return compose_exp_common(list, "{", "}")
end

local function compose_conditional(cond)
   if type(cond) ~= "table" then
	  return "("..tostring(cond)..")"
   end
   return compose_exp_common(cond, "(", ")")
end

local function compose_constraint(const)
   if type(const) ~= "table" then
	  return "("..tostring(const)..")"
   end
   return compose_exp_common(const, "(", ")")
end

local function compose_classperms(classperms)
   if type(classperms) ~= "table" then
	  -- classpermset
	  return tostring(classperms)
   elseif #classperms ~= 2 then
	  MSG.warning("Class permissions have the wrong number of elements")
	  return "{}"
   else
	  local class = tostring(classperms[1])
	  local perms = compose_set(classperms[2])
	  return class.." "..perms
   end
end

local function compose_xperms(xperms)
   if type(xperms) ~= "table" then
	  return tostring(xperms)
   elseif #xperms == 1 then
	  return xperms[1]
   else
	  local buf = {}
	  for i = 1,#xperms do
		 if type(xperms[i]) == "table" then
			local xp = xperms[i]
			if #xp ~= 2 then
			   MSG.warning("Range in xperms does not have two members")
			   return "[]"
			end
			buf[#buf+1] = "["..xp[1].." "..xp[2].."]"
		 else
			buf[#buf+1] = xperms[i]
		 end
	  end
   end
   return "{"..table.concat(buf," ").."}"
end

local function compose_categories(cats)
   local buf = {}
   if type(cats) ~= "table" then
	  buf[#buf+1] = tostring(cats)
   else
	  for i = 1,#cats do
		 if type(cats[i]) == "table" then
			local cs = cats[i]
			if #cs ~= 2 then
			   MSG.warning("Range in category list does not have two members")
			   return "[]"
			end
			buf[#buf+1] = "["..cs[1].." "..cs[2].."]"
		 else
			buf[#buf+1] = cats[i]
		 end
	  end
   end
   return "{"..table.concat(buf," ").."}"
end

local function compose_level(level)
   if type(level) ~= "table" then
	  -- level alias
	  return tostring(level)
   elseif #level > 2 then
	  MSG.warning("Level has more then two parts")
	  return "{}"
   else
	  local s = tostring(level[1])
	  if level[2] then
		 c = compose_categories(level[2])
		 return s.." "..c
	  end
	  return s
   end
end

local function compose_range(range)
   if type(range) ~= "table" then
	  -- range alias
	  return tostring(range)
   elseif #range > 2 then
	  MSG.warning("Range has more then two parts")
	  return "{}"
   else
	  local l1 = compose_level(range[1])
	  if range[2] then
		 local l2 = compose_level(range[2])
		 return "{{"..l1.."} {"..l2.."}}"
	  else
		 return "{"..l1.."}"
	  end
   end
end

local function compose_context(context)
   if type(context) ~= "table" then
	  -- context alias
	  return tostring(context)
   elseif #context == 1 and context[1] == "<<none>>" then
	  return context[1]
   elseif #context < 3 or #context > 4 then
	  MSG.warning("Context has wrong number of elements")
	  MSG.warning(MSG.compose_table(context, "{","}"))
	  return "{}"
   else
	  local buf = {}
	  buf[#buf+1] = tostring(context[1])
	  buf[#buf+1] = tostring(context[2])
	  buf[#buf+1] = tostring(context[3])
	  if context[4] then
		 buf[#buf+1] = compose_range(context[4])
	  end
	  return "{"..table.concat(buf," ").."}"
   end
end

local function compose_number_range(range)
   if type(range) ~= "table" then
	  return tostring(range)
   else
	  if #range == 1 then
		 return tostring(range[1])
	  elseif #range ~= 2 then
		 MSG.warning("Range does not have two members")
		 return "[]"
	  else
		 return "["..range[1].." "..range[2].."]"
	  end
   end
end

local function compose_call_args(args)
   local buf = {}
   for i=1,#args do
	  local a = args[i]
	  if type(a) == "table" then
		 buf[#buf+1] = compose_exp_common(a, "{", "}")
	  else
		 buf[#buf+1] = tostring(a)
	  end
   end
   return "("..table.concat(buf,", ")..")"
end

-------------------------------------------------------------------------------
local function buffer_decl_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local kind = tostring(data[1])
   local name = tostring(data[2])
   local str = "decl "..kind.." "..name..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_order_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local kind = tostring(data[1])
   local list = compose_enclosed_list(data[2])
   local str = "order "..kind.." "..list..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_alias_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local kind = tostring(data[1])
   local name = tostring(data[2])
   local str = "alias "..kind.." "..name..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_attribute_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local kind = tostring(data[1])
   local name = tostring(data[2])
   local str = "attribute "..kind.." "..name..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_policycap_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local caps = compose_list(data[1])
   local str = "policycap "..caps..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_bool_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local bool = tostring(data[1])
   local value = tostring(data[2])
   local str = "bool "..bool.." "..value..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_tunable_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local tunable = tostring(data[1])
   local value = tostring(data[2])
   local str = "tunable "..tunable.." "..value..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_sid_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local sid = tostring(data[1])
   local context = compose_context(data[2])
   local str = "sid "..sid.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_classcommon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local class = tostring(data[1])
   local common= tostring(data[2])
   local str = "classcommon "..class.." "..common..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_common_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local common= tostring(data[1])
   local perm_list = compose_enclosed_list(data[2])
   local str = "common "..common.." "..perm_list..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_class_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local class = tostring(data[1])
   local perm_list = compose_enclosed_list(data[2])
   local str = "class "..class.." "..perm_list..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_classpermset_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local name = tostring(data[1])
   local classperms = compose_classperms(data[2])
   local str = "classpermset "..name.." "..classperms..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_default_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local kind = tostring(data[1])
   local class_list = compose_list(data[2])
   local object = tostring(data[3])
   local str
   if kind == "range" then
	  local range = tostring(data[4])
	  str = "default "..kind.." "..class_list.." "..object.." "..range..";"
   else
	  str = "default "..kind.." "..class_list.." "..object..";"
   end
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_sensitivityaliases_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local sensitivity = tostring(data[1])
   local aliases = compose_list(data[2])
   local str = "sensitivityaliases "..sensitivity.." "..aliases..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_categoryaliases_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local category = tostring(data[1])
   local aliases = compose_list(data[2])
   local str = "category "..category.." "..aliases..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_level_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local level = compose_level(data[1])
   local str = "level "..level..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_aliaslevel_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local alias = tostring(data[1])
   local level = compose_level(data[2])
   local str = "aliaslevel "..alias.." "..level..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_aliasrange_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local alias = tostring(data[1])
   local range = compose_range(data[2])
   local str = "aliasrange "..alias.." "..range..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_typealiases_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local name = tostring(data[1])
   local aliases = compose_enclosed_list(data[2])
   local str = "typealiases "..name.." "..aliases..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_typeattributes_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local name = tostring(data[1])
   local attrs = compose_enclosed_list(data[2])
   local str = "typeattributes "..name.." "..attrs..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_typebounds_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local parent = tostring(data[1])
   local child = tostring(data[2])
   local str = "typebounds "..parent.." "..child..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_permissive_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local name = tostring(data[1])
   local str = "permissive "..name..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_av_rule(buf, node)
   local kind = NODE.get_kind(node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local perms = compose_set(data[4])
   local str = kind.." "..src.." "..tgt.." "..class.." "..perms..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_xperm_rule(buf, node)
   local kind = NODE.get_kind(node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local perms = compose_set(data[4])
   local xperms = compose_xperms(data[5])
   local str = kind.." "..src.." "..tgt.." "..class.." "..perms.." "..xperms..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_typetransition_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local obj = tostring(data[4])
   local file = data[5] or "*"
   local str = "typetransition "..src.." "..tgt.." "..class.." "..obj.." "..file..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_typechange_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local obj = tostring(data[4])
   local str = "typechange "..src.." "..tgt.." "..class.." "..obj..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_typemember_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = compose_list(data[3])
   local obj = tostring(data[4])
   local str = "typemember "..src.." "..tgt.." "..class.." "..obj..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_rangetransition_rule(buf, node)
   local kind = NODE.get_kind(node)
   local data = NODE.get_data(node) or {}
   local src = compose_set(data[1])
   local tgt = compose_set(data[2])
   local class = data[3] or "nil"
   local range = compose_range(data[4])
   local str = "rangetransition "..src.." "..tgt.." "..class.." "..range..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_roletypes_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local role = tostring(data[1])
   local types = compose_list(data[2])
   local str = "roletypes "..role.." "..types..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_roleattributes_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local role = tostring(data[1])
   local attrs = compose_list(data[2])
   local str = "roleattributes "..role.." "..attrs..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_roleallow_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local role1 = tostring(data[1])
   local role2 = tostring(data[2])
   local str = "roleallow "..role1.." "..role2..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_roletransition_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local roles = compose_set(data[1])
   local types = compose_set(data[2])
   local class = tostring(data[3])
   local role2 = tostring(data[4])
   local str = "roletransition "..roles.." "..types.." "..class.." "..role2..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_userroles_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local user = tostring(data[1])
   local roles = compose_list(data[2])
   str = "userrole "..user.." "..roles..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_userlevel_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local user = tostring(data[1])
   local mls_level = data[2] and compose_level(data[2])
   str = "userlevel "..user.." "..mls_level..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_userrange_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local user = tostring(data[1])
   local mls_range = data[2] and compose_range(data[2])
   str = "userrange "..user.." "..mls_range..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_constrain_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local kind = NODE.get_kind(node)
   local class = compose_list(data[1])
   local perms = compose_set(data[2])
   local cstr = compose_constraint(data[3])
   local str = kind.." "..class.." "..perms.." "..cstr..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_validatetrans_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local kind = NODE.get_kind(node)
   local class = compose_list(data[1])
   local cstr = compose_constraint(data[2])
   local str = kind.." "..class.." "..cstr..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_filecon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local path = tostring(data[1])
   local file_type = tostring(data[2])
   local context = compose_context(data[3])
   local str = "filecon "..path.." "..file_type.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_fsuse_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local fs_type = tostring(data[1])
   local fs_name = tostring(data[2])
   local context = compose_context(data[3])
   local str = "fsuse "..fs_type.." "..fs_name.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_genfscon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local fs_name = tostring(data[1])
   local path = tostring(data[2])
   local file_type = tostring(data[3])
   local context = compose_context(data[4])
   local str = "genfscon "..fs_name.." "..path.." "
   if file_type == "all" then
	  str = str..context..";"
   else
	  str = str..file_type.." "..context..";"
   end
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_portcon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local protocol = tostring(data[1])
   local portnum = compose_number_range(data[2])
   local context = compose_context(data[3])
   local str = "portcon "..protocol.." "..portnum.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_netifcon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local interface = tostring(data[1])
   local if_context = compose_context(data[2])
   local packet_context = compose_context(data[3])
   local str = "netifcon "..interface.." "..if_context.." "..packet_context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_nodecon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local ver = tostring(data[1])
   local addr4 = tostring(data[2])
   local mask4 = tostring(data[3])
   local context = compose_context(data[4])
   local str = "nodecon "..ver.." "..addr4.." "..mask4.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_pirqcon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local value = tostring(data[1])
   local context = compose_context(data[2])
   local str = "pirqcon "..value.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_iomemcon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local value = compose_number_range(data[1])
   local context = compose_context(data[2])
   local str = "iomemcon "..value.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_ioportcon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local value = compose_number_range(data[1])
   local context = compose_context(data[2])
   local str = "ioportcon "..value.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_pcidevicecon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local value = compose_number_range(data[1])
   local context = compose_context(data[2])
   local str = "pcidevicecon "..value.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_devicetreecon_rule(buf, node)
   local data = NODE.get_data(node) or {}
   local path = tostring(data[1])
   local context = compose_context(data[2])
   local str = "devicetreecon "..value.." "..context..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_call_rule(buf, node)
   local name = MACRO.get_call_name(node)
   local args = MACRO.get_call_orig_args(node)
   local str_args = compose_call_args(args)
   local str = "call "..tostring(name)..str_args..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_def_rule(buf, node)
   local node_data = NODE.get_data(node)
   local kind = node_data[1]
   local name = node_data[2]
   local list
   if kind == "class" then
	  list = compose_list(node_data[3])
   elseif kind == "perm" then
	  list = compose_list(node_data[3])
   elseif kind == "cstr_exp" then
	  list = compose_constraint(node_data[3])
   else
	  MSG.error_message("Unknown def rule: "..tostring(name))
   end
   local str = "def "..kind.." "..tostring(name).." "..list..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_order_rule(buf, node)
   local node_data = NODE.get_data(node)
   local flavor = tostring(node_data[1])
   local order = compose_enclosed_list(node_data[2])
   local str = "order "..flavor.." "..order..";"
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_comment_rule(buf, node)
   local node_data = NODE.get_data(node)
   local comment = node_data[1]
   local str = "#"..tostring(comment)
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_blank_rule(buf, node)
   local node_data = NODE.get_data(node)
   local str = ""
   BUFFER.buffer_add_str(buf, str)
end

local function buffer_module_rule(buf, node)
   -- Do nothing
end

local simpl_rules = {
   ["decl"] = buffer_decl_rule,
   ["order"] = buffer_order_rule,
   ["alias"] = buffer_alias_rule,
   ["attribute"] = buffer_attribute_rule,
   ["policycap"] = buffer_policycap_rule,
   ["bool"] = buffer_bool_rule,
   ["tunable"] = buffer_tunable_rule,
   ["sid"] = buffer_sid_rule,
   ["classcommon"] = buffer_classcommon_rule,
   ["common"] = buffer_common_rule,
   ["class"] = buffer_class_rule,
   ["classpermset"] = buffer_classpermset_rule,
   ["default"] = buffer_default_rule,
   ["sensitivityaliases"] = buffer_sensitivityaliases_rule,
   ["categoryaliases"] = buffer_categoryaliases_rule,
   ["level"] = buffer_level_rule,
   ["aliaslevel"] = buffer_aliaslevel_rule,
   ["aliasrange"] = buffer_aliasrange_rule,
   ["typealiases"] = buffer_typealiases_rule,
   ["typeattributes"] = buffer_typeattributes_rule,
   ["typebounds"] = buffer_typebounds_rule,
   ["permissive"] = buffer_permissive_rule,
   ["allow"] = buffer_av_rule,
   ["auditallow"] = buffer_av_rule,
   ["dontaudit"] = buffer_av_rule,
   ["neverallow"] = buffer_av_rule,
   ["allowxperm"] = buffer_xperm_rule,
   ["auditallowx"] = buffer_xperm_rule,
   ["dontauditx"] = buffer_xperm_rule,
   ["neverallowx"] = buffer_xperm_rule,
   ["typetransition"] = buffer_typetransition_rule,
   ["typechange"] = buffer_typechange_rule,
   ["typemember"] = buffer_typemember_rule,
   ["rangetransition"] = buffer_rangetransition_rule,
   ["roletypes"] = buffer_roletypes_rule,
   ["roleattributes"] = buffer_roleattributes_rule,
   ["roleallow"] = buffer_roleallow_rule,
   ["roletransition"] = buffer_roletransition_rule,
   ["userroles"] = buffer_userroles_rule,
   ["userlevel"] = buffer_userlevel_rule,
   ["userrange"] = buffer_userrange_rule,
   ["constrain"] = buffer_constrain_rule,
   ["mlsconstrain"] = buffer_constrain_rule,
   ["validatetrans"] = buffer_validatetrans_rule,
   ["mlsvalidatetrans"] = buffer_validatetrans_rule,
   ["filecon"] = buffer_filecon_rule,
   ["fsuse"] = buffer_fsuse_rule,
   ["genfscon"] = buffer_genfscon_rule,
   ["portcon"] = buffer_portcon_rule,
   ["netifcon"] = buffer_netifcon_rule,
   ["nodecon"] = buffer_nodecon_rule,
   ["pirqcon"] = buffer_pirqcon_rule,
   ["iomemcon"] = buffer_iomemcon_rule,
   ["ioportcon"] = buffer_ioportcon_rule,
   ["pcidevicecon"] = buffer_pcidevicecon_rule,
   ["devicetreecon"] = buffer_devicetreecon_rule,
   ["call"] = buffer_call_rule,
   ["def"] = buffer_def_rule,
   ["order"] = buffer_order_rule,
   ["comment"] = buffer_comment_rule,
   ["blank"] = buffer_blank_rule,
   ["module"] = buffer_module_rule, -- Skip
}

-------------------------------------------------------------------------------
local function buffer_block_rules(buf, block, do_rules, do_blocks)
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if do_rules and do_rules[kind] then
		 do_rules[kind](buf, cur)
	  elseif do_blocks and do_blocks[kind] then
		 do_blocks[kind](buf, cur, do_rules, do_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
end

local function buffer_conditional_rules(buf, node, do_rules, do_blocks)
   local then_block = NODE.get_then_block(node)
   local else_block = NODE.get_else_block(node)
   if then_block then
	  BUFFER.buffer_increase_depth(buf)
	  buffer_block_rules(buf, then_block, do_rules, do_blocks)
	  BUFFER.buffer_decrease_depth(buf)
   end
   if else_block then
	  BUFFER.buffer_add_str(buf, "} else {")
	  BUFFER.buffer_increase_depth(buf)
	  buffer_block_rules(buf, else_block, do_rules, do_blocks)
	  BUFFER.buffer_decrease_depth(buf)
   end
end

local function buffer_ifdef_block(buf, node, do_rules, do_blocks)
   local cond_data = IFDEF.get_conditional(node)
   local cond = compose_conditional(cond_data)
   local str = "ifdef "..cond.." {"
   BUFFER.buffer_add_str(buf, str)
   buffer_conditional_rules(buf, node, do_rules, do_blocks)
   BUFFER.buffer_add_str(buf, "}")
end

local function buffer_ifelse_block(buf, node, do_rules, do_blocks)
   local cond_data = NODE.get_data(node)
   local v1 = cond_data[1]
   local v2 = cond_data[2]

   local cond = tostring(v1)
   if v2 then
	  cond = cond.." == "..tostring(v2)
   end
   local str = "ifdef "..cond.." {"
   BUFFER.buffer_add_str(buf, str)
   buffer_conditional_rules(buf, node, do_rules, do_blocks)
   BUFFER.buffer_add_str(buf, "}")
end

local function buffer_tunif_block(buf, node, do_rules, do_blocks)
   local cond_data = IFDEF.get_conditional(node)
   local cond = compose_conditional(cond_data)
   local str = "tunif "..cond.." {"
   BUFFER.buffer_add_str(buf, str)
   buffer_conditional_rules(buf, node, do_rules, do_blocks)
   BUFFER.buffer_add_str(buf, "}")
end

local function buffer_boolif_block(buf, node, do_rules, do_blocks)
   local cond_data = IFDEF.get_conditional(node)
   local cond = compose_conditional(cond_data)
   local str = "boolif "..cond.." {"
   BUFFER.buffer_add_str(buf, str)
   buffer_conditional_rules(buf, node, do_rules, do_blocks)
   BUFFER.buffer_add_str(buf, "}")
end

local function buffer_optional_block(buf, node, do_rules, do_blocks)
   BUFFER.buffer_add_str(buf, "optional")
   BUFFER.buffer_add_str(buf, "{")
   buffer_conditional_rules(buf, node, do_rules, do_blocks)
   BUFFER.buffer_add_str(buf, "}")
end

local function args_to_string(macro)
   local flavors = MACRO.get_def_orig_flavors(macro)
   local buf = {}
   local i = 1
   local arg = "$"..tostring(i)
   while flavors[i] do
	  if type(flavors[i]) ~= "table" then
		 buf[i] = flavors[i].." "..arg
	  else
		 buf[i] = "string "..arg
	  end
	  i = i + 1
	  arg = "$"..tostring(i)
   end
   return table.concat(buf,", ")
end

local function buffer_require_rules(buf, node)
   local requires = MACRO.get_def_requires(node)
   if type(requires) == "boolean" then
	  return
   end
   local keys = TABLE.get_sorted_list_of_keys(requires)
   for i=1,#keys do
	  local t = keys[i]
	  if t == "class" then
		 local classes = TABLE.get_sorted_list_of_keys(requires[t])
		 if #classes == 1 then
			local c = classes[1]
			local perms = TABLE.get_sorted_list_of_keys(requires[t][c])
			local cp = compose_classperms({c,perms})
			BUFFER.buffer_add_str(buf, "require class "..cp..";")
		 else
			local cp_buf = {}
			for j=1,#classes do
			   local c = classes[j]
			   local perms = TABLE.get_sorted_list_of_keys(requires[t][c])
			   local cp = compose_classperms({c,perms})
			   cp_buf[#cp_buf+1] = "{"..cp.."}"
			end
			local cp_str = table.concat(cp_buf," ")
			BUFFER.buffer_add_str(buf, "require class ".." {"..cp_str.."};")
		 end
	  else
		 local values = compose_list(TABLE.get_sorted_list_of_keys(requires[t]))
		 BUFFER.buffer_add_str(buf, "require "..t.." "..values..";")
	  end
   end
end

local function process_compound_args(macro)
   local macro_name = MACRO.get_def_name(macro)
   local cmpd_args = MACRO.get_def_compound_args(macro)
   local cargs = {}
   if cmpd_args then
	  local names = TABLE.get_sorted_list_of_keys(cmpd_args)
	  for i=1,#names do
		 local name = names[i]
		 cargs[name] = macro_name..tostring(i)
	  end
   end
   return cargs
end

local function buffer_compound_args(buf, cargs)
   local arg_names = TABLE.get_sorted_list_of_keys(cargs)
   for i=1,#arg_names do
	  local cmpd_arg = arg_names[i]
	  local name = cargs[cmpd_arg]
	  local str_list = {}
	  local cur, s, e, arg
	  s = 1
	  cur = 1
	  s,e,arg = string.find(cmpd_arg, "(%$%d+)", cur)
	  while s do
		 if s > cur then
			str_list[#str_list+1] = string.sub(cmpd_arg, cur, s-1)
		 end
		 str_list[#str_list+1] = arg
		 cur = e + 1
		 s,e,arg = string.find(cmpd_arg, "(%$%d+)", cur)
	  end
	  if cur < #cmpd_arg then
		 str_list[#str_list+1] = string.sub(cmpd_arg, cur)
	  end
	  local str_list_str = table.concat(str_list, " ")
	  BUFFER.buffer_add_str(buf, "string "..name.." {"..str_list_str.."};")
   end
end

local function replace_compound_args(buf, start, cargs)
   for i=start,#buf do
	  local line = buf[i]
	  if line then
		 local s,n = string.gsub(line, "[%S]+", cargs)
		 if s and n > 0 then
			buf[i] = s
		 end
	  end
   end
end

local function buffer_macro_block(buf, node, do_rules, do_blocks)
   local name = MACRO.get_def_name(node)
   local args = args_to_string(node)
   BUFFER.buffer_add_str(buf, "macro "..tostring(name).."("..args..")")
   BUFFER.buffer_add_str(buf, "{")
   BUFFER.buffer_increase_depth(buf)
   local start = #buf
   buffer_require_rules(buf, node)
   local cargs = process_compound_args(node)
   buffer_compound_args(buf, cargs)
   buffer_block_rules(buf, NODE.get_block(node), do_rules, do_blocks)
   BUFFER.buffer_decrease_depth(buf)
   BUFFER.buffer_add_str(buf, "}")
   replace_compound_args(buf, start, cargs)
end

local simpl_blocks = {
   ["ifdef"] = buffer_ifdef_block,
   ["ifelse"] = buffer_ifelse_block,
   ["tunif"] = buffer_tunif_block,
   ["boolif"] = buffer_boolif_block,
   ["optional"] = buffer_optional_block,
   ["macro"] = buffer_macro_block,
}

-------------------------------------------------------------------------------
local function write_fc_file(out, block)
   local buf = BUFFER.buffer_get_new_buffer(4, 80)
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if kind == "filecon" then
		 buffer_filecon_rule(buf, cur)
	  elseif kind == "comment" then
		 buffer_comment_rule(buf, cur)
	  elseif kind == "blank" then
		 buffer_blank_rule(buf, cur)
	  elseif kind == "tunif" then
		 buffer_tunif_block(buf, cur, simpl_rules, simpl_blocks)
	  elseif kind == "ifdef" then
		 buffer_ifdef_block(buf, cur, simpl_rules, simpl_blocks)
	  elseif kind == "optional" then
		 buffer_optional_block(buf, cur, simpl_rules, simpl_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
   BUFFER.buffer_write(out, buf)
end

local function write_if_file(out, block)
   local buf = BUFFER.buffer_get_new_buffer(4, 80)
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if simpl_rules[kind] then
		 simpl_rules[kind](buf, cur)
	  elseif simpl_blocks[kind] then
		 simpl_blocks[kind](buf, cur, simpl_rules, simpl_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
   BUFFER.buffer_write(out, buf)
end

local function write_te_file(out, block)
   local buf = BUFFER.buffer_get_new_buffer(4, 80)
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if simpl_rules[kind] then
		 simpl_rules[kind](buf, cur)
	  elseif simpl_blocks[kind] then
		 simpl_blocks[kind](buf, cur, simpl_rules, simpl_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
   BUFFER.buffer_write(out, buf)
end

local function write_misc_file(out, block)
   local buf = BUFFER.buffer_get_new_buffer(4, 80)
   local cur = block
   while cur do
	  kind = NODE.get_kind(cur)
	  if simpl_rules[kind] then
		 simpl_rules[kind](buf, cur)
	  elseif simpl_blocks[kind] then
		 simpl_blocks[kind](buf, cur, simpl_rules, simpl_blocks)
	  else
		 TREE.warning("Did not expect this: "..tostring(kind), block)
	  end
	  cur = NODE.get_next(cur)
   end
   BUFFER.buffer_write(out, buf)
end

-------------------------------------------------------------------------------
local function gather_module_and_misc_files(node, kind, do_action, do_block, data)
   local filename = NODE.get_file_name(node)

   local s,e,mod,suffix = string.find(filename,"/([%w%_%-]+)%.(%w%w)$")
   if suffix == "fc" or suffix == "if" or suffix == "te" then
	  data.modules[mod] = data.modules[mod] or {}
	  data.modules[mod][suffix] = node
   else
	  data.misc_files[filename] = node
   end
end
simpl_write.gather_module_and_misc_files = gather_module_and_misc_files

-------------------------------------------------------------------------------
local function get_dirs_and_filename_from_full_path(full_path, common_path)
   local path = full_path
   if common_path then
	  local s,e = string.find(path, common_path)
	  if e then
		 path = string.sub(path,e+1)
	  end
   end
   local dirs = {}
   local s,e,pos,dirname
   pos = 1
   s,e,dirname = string.find(path,"([^%/]+)/")
   while e do
	  dirs[#dirs+1] = dirname
	  pos = e + 1
	  s,e,dirname = string.find(path,"([^%/]+)/",pos)
   end
   local filename = string.sub(path,pos)

   return dirs, filename
end

local function create_dirs(dirs, out_dir)
   local path = out_dir
   if next(dirs) then
	  -- Create all directories that need to be created
	  for i=1,#dirs do
		 local dir = dirs[i]
		 path = path.."/"..dir
		 local d = io.open(path)
		 if not d then
			local res, err = LIBSIMPL.make_dir(path)
			if not res then
			   MSG.error_message(err)
			end
		 else
			d:close()
		 end
	  end
   end
end

local function open_file(dirs, filename, out_dir)
   local path = out_dir
   if next(dirs) then
	  for i=1,#dirs do
		 path = path.."/"..dirs[i]
	  end
   end
   path = path.."/"..filename
   local out_file = io.open(path,"w")
   if not out_file then
	  MSG.error_message("Failed to open "..path)
   end
   return out_file
end

local function write_misc_files(misc_files, common_path, out_dir)
   local misc_file_names = TABLE.get_sorted_list_of_keys(misc_files)
   for i=1,#misc_file_names do
	  local misc_file_name = misc_file_names[i]
	  local node = misc_files[misc_file_name]
	  local out
	  local full_path = NODE.get_file_name(node)
	  if out_dir then
		 local dirs, filename = get_dirs_and_filename_from_full_path(full_path,
																	 common_path)
		 create_dirs(dirs, out_dir)
		 out = open_file(dirs, filename, out_dir)
	  else
		 io.stdout:write("# FILE: "..full_path.."\n")
		 out = io.stdout
	  end
	  write_misc_file(out, NODE.get_block_1(node))

	  if out_dir then
		 out:close()
	  end
   end
end
simpl_write.misc_files = write_misc_files

local function write_modules(modules, common_path, out_dir)
   local module_names = TABLE.get_sorted_list_of_keys(modules)
   for i=1,#module_names do
	  local module_name = module_names[i]
	  local modtab = modules[module_name]
	  local out
	  local te_node = modtab["te"]
	  local if_node = modtab["if"]
	  local fc_node = modtab["fc"]
	  local full_path = NODE.get_file_name(te_node)
	  if out_dir then
		 local dirs, filename = get_dirs_and_filename_from_full_path(full_path,
																	 common_path)
		 create_dirs(dirs, out_dir)
		 out = open_file(dirs, module_name, out_dir)
		 write_te_file(out, NODE.get_block_1(te_node))
		 write_if_file(out, NODE.get_block_1(if_node))
		 write_fc_file(out, NODE.get_block_1(fc_node))
		 out:close()
	  else
		 out = io.stdout
		 io.stdout:write("# FILE: "..tostring(NODE.get_file_name(te_node)).."\n")
		 write_te_file(out, NODE.get_block_1(te_node))
		 io.stdout:write("# FILE: "..tostring(NODE.get_file_name(if_node)).."\n")
		 write_if_file(out, NODE.get_block_1(if_node))
		 io.stdout:write("# FILE: "..tostring(NODE.get_file_name(fc_node)).."\n")
		 write_fc_file(out, NODE.get_block_1(fc_node))
	  end
   end
end
simpl_write.write_modules = write_modules

-------------------------------------------------------------------------------
local function add_order_helper(node, order_flavor, filename, order)
   local cur = node
   local last
   while cur do
	  local kind = NODE.get_kind(cur)
	  if kind == "decl" then
		 local node_data = NODE.get_data(cur) or {}
		 local flavor = node_data[1]
		 if flavor == order_flavor then
			local name = node_data[2]
			order[#order+1] = name
			last = cur
		 end
	  end
	  local block1 = NODE.get_block_1(cur)
	  local block2 = NODE.get_block_2(cur)
	  if block1 then
		 local last1 = add_order_helper(block1, order_flavor, filename, order)
		 last = last1 or last
	  end
	  if block2 then
		 local last1 = add_order_helper(block2, order_flavor, filename, order)
		 last = last1 or last
	  end
	  cur = NODE.get_next(cur)
   end
   return last
end

local function add_order(node, order_flavor, filename)
   local order = {}
   local last = add_order_helper(node, order_flavor, filename, order)
   if last then
	  local new = NODE.create("order", node, filename, NODE.get_line_number(last))
	  NODE.set_data(new, {order_flavor, order})
	  TREE.add_node(last, new)
   else
	  MSG.warning("Failed to add "..tostring(order_flavor)..
				  " order statement to file "..tostring(filename))
   end
end

local function add_orders_to_files(node, kind, do_action, do_block, data)
   local filename = NODE.get_file_name(node)
   if string.find(filename, "security_classes$") then
	  add_order(NODE.get_block_1(node), "class", filename)
   elseif string.find(filename, "initial_sids$") then
	  add_order(NODE.get_block_1(node), "sid", filename)
   elseif string.find(filename, "mls$") then
	  add_order(NODE.get_block_1(node), "category", filename)
   elseif string.find(filename, "mcs$") then
	  add_order(NODE.get_block_1(node), "category", filename)
   end
end

local function add_orders_to_policy(head)
   local action = {
	  ["file"] = add_orders_to_files,
   }
   TREE.walk_normal_tree(head, action, nil)
end

-------------------------------------------------------------------------------
local function write_simpl(head, out_dir, verbose)
   MSG.verbose_out("\nWrite SIMPL from Refpolicy", verbose, 0)

   if out_dir then
	  f = io.open(out_dir,"r")
	  if f then
		 f:close()
		 LIBSIMPL.remove_dir(out_dir)
	  end
	  local res, err = LIBSIMPL.make_dir(out_dir)
	  if not res then
		 MSG.error_message(err)
	  end
   end

   local file_action = {
	  ["file"] = gather_module_and_misc_files,
   }

   local modules = {}
   local misc_files = {}
   local file_data = {
	  ["modules"] = modules,
	  ["misc_files"] = misc_files,
   }

   add_orders_to_policy(NODE.get_block_1(head))
   TREE.walk_normal_tree(NODE.get_block_1(head), file_action, file_data)
   TREE.disable_active(head)
   TREE.enable_inactive(head)
   add_orders_to_policy(NODE.get_block_2(head))
   TREE.walk_normal_tree(NODE.get_block_2(head), file_action, file_data)
   TREE.disable_inactive(head)
   TREE.enable_active(head)

   local common_path = find_common_path(head)

   write_misc_files(misc_files, common_path, out_dir)
   write_modules(modules, common_path, out_dir)
end
simpl_write.write_simpl = write_simpl

-------------------------------------------------------------------------------
return simpl_write
