#!/usr/bin/lua
--[[
Mercury: http://github.com/nrk/mercury/
Xavante: http://www.keplerproject.org/xavante/

Usage: ./run-with-xavante APPNAME
]]

require 'luarocks.require'
require 'xavante'
require 'wsapi.xavante'

if not arg[1] then
    print([[
Please specify a mercury application to boot with Xavante, e.g.:

  ./run-with-xavante greetings
]])
    os.exit(1)
end

-- TODO: checks and more options

local application = arg[1]

xavante.HTTP{
    server = {host = "127.0.0.1", port = 7654},

    defaultHost = {
        rules = {
            {
                match = { "^/(.-)$" },
                with = wsapi.xavante.makeHandler(application)
            } 
        }
    }
}

xavante.start()
