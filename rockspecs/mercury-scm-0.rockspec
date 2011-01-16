package = "mercury"
version = "scm-0"
source = {
    url = "git://github.com/nrk/mercury.git"
}
description = {
    summary = "A small framework for creating web apps in Lua",
    detailed = [[
        Mercury aims to be a Sinatra-like web framework (or DSL, if you like) for
        creating web applications in Lua, quickly and painlessly.
    ]],
    license = "MIT/X11",
    homepage = "http://github.com/nrk/mercury"
}
dependencies = {
    "lua >= 5.1",
    "wsapi",
    "xavante",
    "wsapi-xavante"
}

build = {
    type = "none",
    install = {
        lua = {
            "mercury.lua",
            ["mercury.lp"] = "lp.lua"
        },
        bin = {
            ["mercury"] = "bin/mercury"
        }
    }
}
