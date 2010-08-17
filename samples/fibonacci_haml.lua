require 'luarocks.require'
require 'mercury'
require 'haml'

module('fibonacci_haml', package.seeall, mercury.application)

local templates = {
    index = [[
%html
  %head
    %title Fibonacci numbers generator
    %style(type="text/css")
      :plain
        #fibonateUpTo { width: 50px; border: 1px solid #000; }
    :javascript
      function check_fibonacci() {
        var your_number = parseInt(document.getElementById('your_number').value);
        if (isNaN(your_number)) {
            alert("You must specify a valid number");
            return false;
        }
        return true;
      }
  %body
    %p Welcome to the Fibonacci numbers generator!
    %p You can try one of the following samples:
    %ul
      - for _, maxn in pairs(samples) do
        - local link = "/fibonacci/" .. maxn
        %li
          %a(href=link)= "Generate numbers up to " .. maxn
    %p
      %form(method="post" action="./fibonacci/" onsubmit="return check_fibonacci()")
        %label(for="your_number")
          If you prefer, you can generate Fibonacci numbers up to 
        %input(id="your_number" name="limit" type="text")
        %input(type="submit" value="Try it yourself!")
]],

    fibonacci = [[
%html
  %head
    %title Fibonacci numbers generator
  %body
    %p
      :plain
        Generating Fibonacci numbers up to #{params.limit}!
    %ul
      - for number in fibonacci(tonumber(params.limit)) do
        %li= number
]],
}

helpers(function()
    function get_samples(how_many)
        local samples = {}
        for i = 1, how_many do
            table.insert(samples, math.random(1, 1000000))
        end
        return samples
    end

    function fibonacci(maxn)
        return coroutine.wrap(function()
            local x, y = 0, 1
            while x <= maxn do 
                coroutine.yield(x)
                x, y = y, x + y
            end
        end)
    end
end)

get('/', function() 
    t.haml(templates.index, nil, { samples = get_samples(4) })
end)

get('/fibonacci/:limit', function() 
    t.haml(templates.fibonacci)
end)

post('/fibonacci/', function()
    t.haml(templates.fibonacci)
end)
