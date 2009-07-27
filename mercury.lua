require 'luarocks.require'
require 'wsapi.request'
require 'wsapi.response'
require 'wsapi.util'
require 'base'

module('mercury', package.seeall)

local route_table = { GET = {}, POST = {}, PUT = {}, DELETE = {} }
local application_methods = {}, {}

--
-- *** application methods *** --
--

function application_methods.get(path, method, options) 
    add_route('GET', path, method)
end

function application_methods.post(path, method, options) 
    add_route('POST', path, method)
end

function application_methods.put(path, method, options) 
    add_route('PUT', path, method)
end

function application_methods.delete(path, method, options) 
    add_route('DELETE', path, method)
end

function application_methods.pass()
    error({ pass = true })
end

--
-- *** application *** --
--

function application(application, fun)
    if type(application) == 'string' then
        application = { _NAME = application }
    else
        application = application or {}
    end

    for k, v in pairs(application_methods) do
        application[k] = v
    end

    application.run = function(wsapi_env) 
        return run(application, wsapi_env)
    end

    application.params     = {}
    application.env        = {}
    application.request    = {}
    application.response   = {}

    if fun then 
        setfenv(fun, setmetatable({}, {
            __index = function(_, k) return _G[k] or application[k] end 
        }))()
    end

    return application
end

function add_route(verb, path, handler, options)
    table.insert(route_table[verb], { 
        pattern = path, 
        handler = handler, 
        options = options, 
    })
end

function compile_url_pattern(pattern)
    local compiled_pattern = { 
        original = pattern,
        params   = { },
    }

    -- TODO: this is broken and does not work for complex scenarios, 
    --       we should take a different approach. More to come.
    compiled_pattern.pattern = pattern:gsub(':(%w+)', function(param, l)
        table.insert(compiled_pattern.params, param)
        return '(.-)'
    end)

    return compiled_pattern
end

function extract_parameters(pattern, matches)
    params = { }
    for i,k in ipairs(pattern.params) do
        params[k] = wsapi.util.url_decode(matches[i])
    end
    return params
end

function url_match(pattern, path)
    local matches = { string.match(path, "^" .. pattern.pattern .. "$") }
    if #matches > 0 then
        return true, extract_parameters(pattern, matches)
    else
        return false, nil
    end
end

function router(application, verb, path)
    return coroutine.wrap(function() 
        for _, route in pairs(route_table[verb]) do 
            -- TODO: routes should be compiled upon definition
            local match, params = url_match(compile_url_pattern(route.pattern), path)
            application.params  = params
            if match then 
                -- TODO: application.params? here? no way...
                coroutine.yield(route.handler) 
            end
        end
    end)
end


function initialize(application, wsapi_env)
    -- TODO: taken from Orbit! It will change soon to adapt 
    --       request and response to a more suitable model.
    local web = { 
        status = "200 Ok", 
        headers  = { ["Content-Type"]= "text/html" },
        cookies  = {} 
    }

    web.vars     = wsapi_env
    web.prefix   = application.prefix or wsapi_env.SCRIPT_NAME
    web.suffix   = application.suffix
    web.doc_root = wsapi_env.DOCUMENT_ROOT

    if wsapi_env.APP_PATH == '' then
        web.real_path = application.real_path or '.'
    else
        web.real_path = wsapi_env.APP_PATH
    end

    local wsapi_req = wsapi.request.new(wsapi_env)
    local wsapi_res = wsapi.response.new(web.status, web.headers)

    web.set_cookie = function(_, name, value)
        wsapi_res:set_cookie(name, value)
    end

    web.delete_cookie = function(_, name, path)
        wsapi_res:delete_cookie(name, path)
    end

    web.path_info = wsapi_req.path_info

    if not wsapi_env.PATH_TRANSLATED == '' then
        web.path_translated = wsapi_env.PATH_TRANSLATED 
    else
        web.path_translated = wsapi_env.SCRIPT_FILENAME 
    end

    web.script_name = wsapi_env.SCRIPT_NAME
    web.method      = string.lower(wsapi_req.method)
    web.input       = wsapi_req.params
    web.cookies     = wsapi_req.cookies

    application.env      = wsapi_env
    application.request  = wsapi_req
    application.response = wsapi_res

    return web, wsapi_res
end

function run(application, wsapi_env)
    local request, response = initialize(application, wsapi_env)

    for handler in router(application, wsapi_env.REQUEST_METHOD, wsapi_env.PATH_INFO) do
        -- TODO: I think that in a near future the handler will be setfenv'ed so 
        --       that params are accessible only in the route environment.
        local successful, res = xpcall(handler, debug.traceback)

        if successful then 
            response.status  = application.response.status
            response.headers = application.response.headers
            response:write(res or '')
            return response:finish()
        else
            if not res.pass then
                response.status  = 500
                response.headers = { ['Content-type'] = 'text/html' }
                response:write('<pre>' .. res:gsub("\n", "<br/>") .. '</pre>')
                return response:finish()
            end
        end
    end

    local function emit_no_routes_matched()
        coroutine.yield('<html><head><title>ERROR</title></head><body>')
        coroutine.yield('Sorry, no route found to match ' .. request.path_info .. '<br /><br/>')
        if application.debug_mode then
            coroutine.yield('<code><b>REQUEST DATA:</b><br/>' .. tostring(request) .. '<br/><br/>')
            coroutine.yield('<code><b>RESPONSE DATA:</b><br/>' .. tostring(response) .. '<br/><br/>')
        end
        coroutine.yield('</body></html>')
    end

    return 500, { ['Content-type'] = 'text/html' }, coroutine.wrap(emit_no_routes_matched)
end
