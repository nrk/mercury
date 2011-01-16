require 'wsapi.request'
require 'wsapi.response'
require 'wsapi.util'

module('mercury', package.seeall)

local mercury_env = getfenv()
local route_env   = setmetatable({ }, { __index = _G })
local route_table = { GET = {}, POST = {}, PUT = {}, DELETE = {} }

local application_methods = {
    get    = function(path, method, options) add_route('GET', path, method) end,
    post   = function(path, method, options) add_route('POST', path, method) end,
    put    = function(path, method, options) add_route('PUT', path, method) end,
    delete = function(path, method, options) add_route('DELETE', path, method) end,
    helper  = function(name, method) set_helper(route_env, name, method) end,
    helpers = function(helpers)
        if type(helpers) == 'table' then
            set_helpers(route_env, helpers)
        elseif type(helpers) == 'function' then
            local temporary_env = setmetatable({}, {
                __newindex = function(e,k,v)
                    set_helper(route_env, k, v)
                end,
            })
            setfenv(helpers, temporary_env)()
        else
            -- TODO: raise an error?
        end
    end,
}

function set_helpers(environment, methods)
    for name, method in pairs(methods) do
        set_helper(environment, name, method)
    end
end

function set_helper(environment, name, method)
    if type(method) ~= 'function' then
        error('"' .. name .. '" is an invalid helper, only functions are allowed.')
    end
    environment[name] = setfenv(method, environment)
end

--
-- *** ext functions *** --
--

function merge_tables(...)
    local numargs, out = select('#', ...), {}
    for i = 1, numargs do
        local t = select(i, ...)
        if type(t) == "table" then
            for k, v in pairs(t) do out[k] = v end
        end
    end
    return out
end

--
-- *** route environment *** --
--

(function() setfenv(1, route_env)
-- This is a glorious trick to setup a different environment for routes since
-- Lua functions inherits the environment in which they are *created*! This
-- will not be compatible with Lua 5.2, for which the new _ENV should provide
-- a much more clean way to achieve a similar result.

   -- TODO: Create a function like setup_route_environment(fun)
    local templating_engines = {
        haml     = function(template, options, locals)
            local haml = haml.new(options)
            return function(env)
                return haml:render(template, mercury_env.merge_tables(env, locals))
            end
        end,
        cosmo    = function(template, values)
            return function(env)
                return cosmo.fill(template, values)
            end
        end,
        string   = function(template, ...)
            return function(env)
                return string.format(template, unpack(arg))
            end
        end,
        lp       = function(template, values)
            return function(env)
                local lp = require 'lp'
                return lp.fill(template, mercury_env.merge_tables(env, values))
            end
        end,
    }

    local route_methods = {
        pass = function()
            coroutine.yield({ pass = true })
        end,
        -- Use a table to group template-related methods to prevent name clashes.
        t    = setmetatable({ }, {
            __index = function(env, name)
                local engine = templating_engines[name]

                if type(engine) == nil then
                    error('cannot find template renderer "'.. name ..'"')
                end

                return function(...)
                    coroutine.yield({ template = engine(...) })
                end
            end
        }),
    }

    for k, v in pairs(route_methods) do route_env[k] = v end

setfenv(1, mercury_env) end)()

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

    local mt = { __index = _G }

    if fun then
        setfenv(fun, setmetatable(application, mt))()
    else
        setmetatable(application, mt)
    end

    return application
end

function add_route(verb, path, handler, options)
    table.insert(route_table[verb], {
        pattern = compile_url_pattern(path),
        handler = setfenv(handler, route_env),
        options = options,
    })
end

function error_500(response, output)
    response.status  = 500
    response.headers = { ['Content-type'] = 'text/html' }
    response:write(
        '<pre>An error has occurred while serving this page.\n\n' ..
        'Error details:\n' .. output:gsub("\n", "<br/>") ..
        '</pre>'
    )
    return response:finish()
end

function compile_url_pattern(pattern)
    local compiled_pattern = {
        original = pattern,
        params   = { },
    }

    -- Lua pattern matching is blazing fast compared to regular expressions,
    -- but at the same time it is tricky when you need to mimic some of
    -- their behaviors.
    pattern = pattern:gsub("[%(%)%.%%%+%-%%?%[%^%$%*]", function(char)
        if char == '*' then return ':*' else return '%' .. char end
    end)

    pattern = pattern:gsub(':([%w%*]+)(/?)', function(param, slash)
        if param == '*' then
            table.insert(compiled_pattern.params, 'splat')
            return '(.-)' .. slash
        else
            table.insert(compiled_pattern.params, param)
            return '([^/?&#]+)' .. slash
        end

    end)

    if pattern:sub(-1) ~= '/' then pattern = pattern .. '/' end
    compiled_pattern.pattern = '^' .. pattern .. '?$'

    return compiled_pattern
end

function extract_parameters(pattern, matches)
    local params = { }
    for i,k in ipairs(pattern.params) do
        if (k == 'splat') then
            if not params.splat then params.splat = {} end
            table.insert(params.splat, wsapi.util.url_decode(matches[i]))
        else
            params[k] = wsapi.util.url_decode(matches[i])
        end
    end
    return params
end

function extract_post_parameters(request, params)
    for k,v in pairs(request.POST) do
        if not params[k] then params[k] = v end
    end
end

function url_match(pattern, path)
    local matches = { string.match(path, pattern.pattern) }
    if #matches > 0 then
        return true, extract_parameters(pattern, matches)
    else
        return false, nil
    end
end

function prepare_route(route, request, response, params)
    route_env.params   = params
    route_env.request  = request
    route_env.response = response
    return route.handler
end

function router(application, state, request, response)
    local verb, path = state.vars.REQUEST_METHOD, state.vars.PATH_INFO

    return coroutine.wrap(function()
        local routes = verb == "HEAD" and route_table["GET"] or route_table[verb]
        for _, route in ipairs(routes) do
            local match, params = url_match(route.pattern, path)
            if match then
                if verb == 'POST' then extract_post_parameters(request, params) end
                coroutine.yield(prepare_route(route, request, response, params))
            end
        end
    end)
end

function initialize(application, wsapi_env)
    -- TODO: Taken from Orbit! It will change soon to adapt request
    --       and response to a more suitable model.
    local web = {
        status   = 200,
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

    return web, wsapi_req, wsapi_res
end

function run(application, wsapi_env)
    local state, request, response = initialize(application, wsapi_env)

    for route in router(application, state, request, response) do
        local coroute = coroutine.create(route)
        local success, output = coroutine.resume(coroute)

        if not success then
            return error_500(response, output)
        end

        local output_type = type(output)
        if output_type == 'function' then
            -- First attempt at streaming responses using coroutines.
            return response.status, response.headers, coroutine.wrap(output)
        elseif output_type == 'string' then
            response:write(output)
            return response:finish()
        elseif output.template then
            response:write(output.template(getfenv(route)) or 'template rendered an empty body')
            return response:finish()
        else
            if not output.pass or not success then
                return error_500(response, output)
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

    return 404, { ['Content-type'] = 'text/html' }, coroutine.wrap(emit_no_routes_matched)
end
