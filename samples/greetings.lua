require 'mercury'

module('greetings', package.seeall, mercury.application)

local languages = {
    en = 'Hi %s, how are you?', 
    it = 'Ciao %s, come stai?', 
    ja = '今日は%sさん、お元気ですか。 ' 
}

local response_body = [[
    <html>
      <head>
        <title>Sinatra in Lua? Sure, it is called &quot;Mercury&quot;!</title>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
      </head>
      <body>
        %s
      </body>
    </html>
    ]]

local function localized_message(language)
    return languages[language] or languages.en
end

get('/', function() 
    return response_body:format([[
        Welcome to the first Mercury application ever built!<br /><br />
        <form action="./say_hi/" method="post">
          <fieldset>
            <legend>Please fill in your name and choose your preferred language</legend>
            <input type="text" id="name" name="name" /><br/>
            English<input type="radio" name="lang" value="en"/><br/>
            Italian<input type="radio" name="lang" value="it"/><br/>
            Japanese<input type="radio" name="lang" value="ja"/><br/>
          </fieldset>
          <input type="submit" value="Go on...">
        </form>
    ]])
end)

post('/say_hi/', function() 
    if params.name == '' or not params.name then 
        return response_body:format([[
            Sorry but I do not believe you, you can not have no name ;-)
            Please <a href="javascript:history.go(-1)">try again</a>.
        ]])
    end

    local message = localized_message(params.lang)

    return response_body:format(
        message:format(params.name) .. 
        '<br/><br/>If you do not like POST-based greetings, then ' .. 
        string.format('<a href="../say_hi/%s/%s/">you can try this!</a>', 
            params.lang or 'en', 
            params.name
        )
    )
end)

get('/say_hi/:lang/:name/', function() 
    local message = localized_message(params.lang)
    return response_body:format(message:format(params.name))
end)