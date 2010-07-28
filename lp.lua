----------------------------------------------------------------------------
-- Lua Pages Template Engine.
--
-- Author: Fábio Mascarenhas
-- http://www.lua.inf.puc-rio.br/~mascarenhas/template
---------------------------------------------------------------------------

local find, format, gsub, strsub =
   string.find, string.format, string.gsub, string.sub
local concat, tinsert = table.concat, table.insert
local getfenv, setfenv, setmetatable = getfenv, setfenv, setmetatable
local assert, loadstring, tostring = assert, loadstring, tostring

module(...)

--
-- Builds a piece of Lua code which outputs the (part of the) given string.
-- @param s String.
-- @param i Number with the initial position in the string.
-- @param f Number with the final position in the string (default == -1).
-- @return String with the correspondent Lua code which outputs the part of the string.
--
local function out(s, i, f)
   s = strsub(s, i, f or -1)
   if s == "" then return s end
   -- we could use `%q' here, but this way we have better control
   s = gsub(s, "([\\\n\'])", "\\%1")
   -- substitute '\r' by '\'+'r' and let `loadstring' reconstruct it
   s = gsub(s, "\r", "\\r")
   return format(" __outfunc('%s')", s)
end


----------------------------------------------------------------------------
-- Translate the template to Lua code.
-- @param s String to translate.
-- @return String with translated code.
----------------------------------------------------------------------------
function translate(s)
   s = gsub(s, "<%%(.-)%%>", "<?lua %1 ?>")
   local res = {}
   local start = 1   -- start of untranslated part in `s'
   while true do
      local ip, fp, target, exp, code = find(s, "<%?(%w*)[ \t]*(=?)(.-)%?>", start)
      if not ip then break end
      tinsert(res, out(s, start, ip-1))
      if target ~= "" and target ~= "lua" then
	 -- not for Lua; pass whole instruction to the output
	 tinsert(res, out(s, ip, fp))
      else
	 if exp == "=" then   -- expression?
	    tinsert(res, format(" __outfunc(%s)", code))
	 else  -- command
	    tinsert(res, format(" %s", code))
	 end
      end
      start = fp + 1
   end
   tinsert(res, out(s, start))
   return [[
     local __env, __outfunc = ...
     local __restorenv
     local __result = {}
     if not __outfunc then
	local insert = tinsert
	local tostring = tostring
	__outfunc = function (s) 
		       if s then 
			  insert(__result, tostring(s))
		       end
		    end
     end
     do
       local env = getfenv(1)
       local setfenv = setfenv
       setfenv(1, __env)
       __restoreenv = function ()
			 setfenv(2, env)
		      end
     end
   ]] .. concat(res, "\n") .. [[
      __restoreenv()
      return concat(__result)
   ]]
end

----------------------------------------------------------------------------
-- Internal compilation cache.

local cache = {}
setmetatable(cache, { __index = function (tab, key)
				   local new = {}
				   tab[key] = new
				   return new
				end })

----------------------------------------------------------------------------
-- Translates a template into a Lua function.
-- Does NOT execute the resulting function.
-- Uses a cache of templates.
-- @param string String with the template to be translated.
-- @param chunkname String with the name of the chunk, for debugging purposes.
-- @return Function with the resulting translation.

function compile(string, chunkname)
   chunkname = chunkname or string
   local f, err = cache[string][chunkname]
   if f then return f end
   f = assert(loadstring(translate(string), chunkname))
   setfenv(f, { tinsert = tinsert, concat = concat,
	      getfenv = getfenv, setfenv = setfenv,
	      tostring = tostring})
   cache[string][chunkname] = f
   return f
end

----------------------------------------------------------------------------
-- "Fills" the template using the environment env, and returns the result
-- @param template String with template
-- @param env Global environment for template
-- @return String with result of template application

function fill(template, env)
   local prog = compile(template)
   local out = {}
   local outfunc = function (s)
		      tinsert(out, s)
		   end
   prog(env, outfunc)
   return concat(out)
end

