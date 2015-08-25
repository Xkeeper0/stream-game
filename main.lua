local settings		= require("settings")



package.path = package.path .. ";./?/init.lua"

local json		= require("json")
--local socket	= require("socket")
local irc		= require("irc")
local Game		= require("game")

local ircserv	= nil
local ourGame	= nil
local fonts		= {}
local windowStats	= {}

sounds	= {}

function tprint (tbl, indent)
  if not indent then indent = 0 end
  for k, v in pairs(tbl) do
    formatting = string.rep("  ", indent) .. k .. ": "
    if type(v) == "table" then
      print(formatting)
      tprint(v, indent+1)
    else
      print(formatting .. tostring(v))
    end
  end
end


function activitySorter(p1, p2)

	local skey1	= (ourGame.players[p1].activity * 1000000000) + ourGame.players[p1].activityTimeout * 100000000 + ourGame.players[p1].duration * 1000 + ourGame.playerData[p1].exp
	local skey2	= (ourGame.players[p2].activity * 1000000000) + ourGame.players[p2].activityTimeout * 100000000 + ourGame.players[p2].duration * 1000 + ourGame.playerData[p2].exp

	return skey1 > skey2

end


function gstart(channel, users)
	if (string.lower(channel) == string.lower(settings.channel)) then
		love.window.setTitle(channel .." - streamgame")
		settings.channel	= channel
		ourGame		= Game.start(channel)
		tprint(ourGame)
		for user, t in pairs(users.users) do
			print("Adding to game:", user)
			ourGame:addPlayer(user, channel)
		end

		ircserv:hook("OnChat", 
			function(u, c, m)
				ourGame:playerChat(u.nick, c, m)
			end
			)


		ircserv:hook("OnJoin", 
			function(u, c)
				print("Adding to game:", u.nick)
				ourGame:addPlayer(u.nick, c)
			end
			)

		ircserv:hook("OnPart", 
			function(u, c)
				print("Removing from game:", u.nick)
				ourGame:removePlayer(u.nick, c)
			end
			)

		ircserv:hook("OnQuit", 
			function(u, m)
				print("Removing from game (quit):", u.nick)
				ourGame:removePlayer(u.nick)
			end
			)
	end
end

function love.load()
	love.audio.setVolume(0.5)
	fonts.big		= love.graphics.newFont(18)
	fonts.small		= love.graphics.newFont(12)
	sounds.levelup	= love.audio.newSource("sounds/levelup.ogg", "static")
	sounds.join		= love.audio.newSource("sounds/p-join.ogg", "static")
	sounds.leave	= love.audio.newSource("sounds/p-leave.ogg", "static")

	ircserv			= irc.new{ nick = settings.nick, }

	ircserv:hook("OnChat", function(user, channel, message)
		print(("[%s] %s: %s"):format(channel, user.nick, message))
	end)

	ircserv:hook("OnRaw",
		function(line)
			print("Raw> ".. line)
		end
		)

	ircserv:connect(settings.server)
	ircserv:trackUsers(true)
	ircserv:hook("NameList", 20, gstart)
	ircserv:join(settings.channel)

	local _a, _b, _c	= love.window.getMode()
	windowStats	= { w = _a, h = _b, f = _c }

	tprint(windowStats)

end

function love.update(dt)
	if ourGame then
		ourGame:update(dt)
	end

	if ircserv then
		ircserv:think()
	end

	updateMessages(dt)

end

function love.draw()

	if ourGame then
		--love.graphics.print(string.format("%05.2f s", ourGame.updateTime))
		local i	= 0
		local count	= math.floor(windowStats.h / 35)
		for _, pname in pairs(ourGame.internalPlayers) do
			if i < count then
				local y			= 3 + i * 35
				local player	= ourGame.players[pname]
				local pdata		= ourGame.playerData[pname]
				local pEXP		= (pdata.dexp - pdata.thisLevelExp) / (pdata.nextLevelExp - pdata.thisLevelExp) * 100

				love.graphics.setFont(fonts.big)
				local col		= 128
				if player.activityTimeout > 0 then
					col			= 128 + ((player.activityTimeout / Game.activityTimeout) * 72)
				end
				if player.activity > 0 then
					col			= 200 + math.min(55, player.activity)
				end

				love.graphics.setColor(col, col, col)
				love.graphics.print(pname, 3, y + 8)
				love.graphics.setColor(0, 0, 0)
				love.graphics.rectangle("fill", 135, y, 265, 40)
				love.graphics.setColor(255, 255, 255)
				love.graphics.setFont(fonts.small)
				love.graphics.printf(string.format("Level %d", pdata.level), 140, y, 125, "left")
				love.graphics.printf(string.format("%d EXP", pdata.exp), 143, y, 250, "right")

				drawExpBar(140, y + 16, 250, (pdata.exp - pdata.thisLevelExp) / (pdata.nextLevelExp - pdata.thisLevelExp))
			end
			i = i + 1
		end

	end

	drawMessages()

	--[[
	local i = -30
	for t = 1, 30, 1 do
		i = i + 15
		local v	= Game.getLevelExp(t)
		love.graphics.line(10.5, 50.5 + i, 10.5 + v, 50.5 + i)
		love.graphics.print(t, 120, 50.5 + i)
		love.graphics.print(v, 200, 50.5 + i)
	end
	--]]
end




function love.quit()
	local x = love.filesystem.write(ourGame.channel ..".json", json.encode(ourGame.playerData))
	print("File written state: ", x)
	return false
end

oldErrhand	= love.errhand
function love.errhand(msg)
	print("ERROR!!!", msg)
	print("Attempting to save file data...")
	love.quit()
	print("Running original error handler now...")
	oldErrHand(msg)

end


function drawExpBar(x, y, w, pct)
	love.graphics.translate( 0.5, 0.5 )
	love.graphics.setLineWidth(2)

	love.graphics.setColor(160, 120, 255)
	love.graphics.rectangle("fill", x + 2, y + 2, pct * w, 8)
	love.graphics.setColor(255, 255, 255)
	love.graphics.rectangle("line", x, y, w + 2, 10)
	love.graphics.reset()

end

messages	= {}

function addMessage(t)
	table.insert(messages, { text = t, life = 5 })
	while(#messages > 3) do
		table.remove(messages, 1)
	end
end
function updateMessages(dt)
	for i, m in ipairs(messages) do
		m.life	= m.life - dt
		if m.life < 0 then
			table.remove(messages, i)
		end
	end
end
function drawMessages()
	local c	= #messages
	local y	= windowStats.h - 15
	love.graphics.setColor(0, 0, 0, 200)
	love.graphics.rectangle("fill", 0, (y - 2) - (c - 1) * 12, 400, 100)
	
	for i, m in ipairs(messages) do
		local y	= y - (c - i) * 12
		local color	= math.min(255, (m.life) * 255)
		love.graphics.setColor(color, color, color)
		love.graphics.printf(m.text, 0, y, 400, "center")
	end
	love.graphics.setColor(255, 255, 255)
end