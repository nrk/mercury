-- You can also define your application in a dedicated environment without 
-- polluting Lua's global scope, you can think of it as a sort of Sinatra::Base

require 'mercury'

module(..., package.seeall)

local myapp = mercury.application('no_pollution', function()
    local app_name = _NAME

    get('/', function()
        return string.format('<h1>Welcome to %s!</h1>', app_name)
    end)

    get('/hello/:name', function()
        return string.format('Hello %s!', params.name)
    end)
end)

run = myapp.run
