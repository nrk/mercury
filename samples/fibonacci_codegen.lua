require 'luarocks.require'
require 'mercury'

--[[
    lua-CodeGen is a "safe" template engine.
    see http://fperrad.github.com/lua-CodeGen/
]]

module('fibonacci_codegen', package.seeall, mercury.application)

local templates = {
    index = [[

<html>
  <head>
    <title>Fibonacci numbers generator</title>
    <style type='text/css'>
          #fibonateUpTo { width: 50px; border: 1px solid #000; }
    </style>
    <script type='text/javascript'>
        function check_fibonacci() {
          var your_number = parseInt(document.getElementById('your_number').value);
          if (isNaN(your_number)) {
              alert("You must specify a valid number");
              return false;
          }
          return true;
        }
    </script>
  </head>
  <body>
    <p>Welcome to the Fibonacci numbers generator!!!</p>

    <p>You can try one of the following samples:</p>
    <ul>
      ${samples/_sample_link()}
    </ul>

    <p>
      <form action='./fibonacci/' method='post' onsubmit='return check_fibonacci()'>
        <label for='your_number'>
          If you prefer, you can generate Fibonacci numbers up to
        </label>
        <input id='your_number' name='limit' type='text' />
        <input type='submit' value='Try it yourself!' />
      </form>
    </p>

  </body>
</html>

]],
    _sample_link = [[
<li>
  <a href='/fibonacci/${it}'>Generate numbers up to ${it}</a>
</li>
]],

    fibonacci = [[
<html>
  <head>
    <title>Fibonacci numbers generator</title>
  </head>
  <body>
    <p>
          Generating Fibonacci numbers up to ${params.limit}!!!
    </p>
    <ul>
      ${numbers/_value_item()}
    </ul>
  </body>
</html>
]],
    _value_item = [[
<li>${it}</li>
]],
}

local function get_samples(how_many)
    local samples = {}
    for i = 1, how_many do
        table.insert(samples, math.random(1, 1000000))
    end
    return samples
end

local function fibonacci(maxn)
    return coroutine.wrap(function()
        local x, y = 0, 1
        while x <= maxn do
            coroutine.yield(x)
            x, y = y, x + y
        end
    end)
end

get('/', function()
    t.codegen(templates, 'index', { samples = get_samples(4) })
end)

get('/fibonacci/:limit', function()
    local numbers = {}
    for val in fibonacci(tonumber(params.limit)) do
        numbers[#numbers+1] = val
    end
    t.codegen(templates, 'fibonacci', { numbers = numbers })
end)

post('/fibonacci/', function()
    local numbers = {}
    for val in fibonacci(tonumber(params.limit)) do
        numbers[#numbers+1] = val
    end
    t.codegen(templates, 'fibonacci', { numbers = numbers })
end)
