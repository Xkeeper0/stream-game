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
local lastDt	= 0

sounds	= {}

-- Debug function to recursively print table contents
function tprint (tbl, indent)
	if not indent then indent = 0 end
	for k, v in pairs(tbl) do
		formatting = string.rep("	", indent) .. k .. ": "
		if type(v) == "table" then
			print(formatting)
			tprint(v, indent+1)
		else
			print(formatting .. tostring(v))
		end
	end
end


-- Handle starting of a game with a given channel and users
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
				ourGame:addPlayer(u.nick, c)
			end
			)

		ircserv:hook("OnPart",
			function(u, c)
				ourGame:removePlayer(u.nick, c)
			end
			)

		ircserv:hook("OnQuit",
			function(u, m)
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
	lastDt	= dt
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
		drawPlayers()

	end

	drawMessages()

	--[[
	love.graphics.setColor(0, 0, 0)
	love.graphics.rectangle("fill", 0, 0, 50, 20)
	love.graphics.setColor(255, 255, 255)
	love.graphics.print(string.format("%08.7f\n%3.1f", lastDt, lastDt / (1 / 60) * 60), 0, 0)
	--]]

end



function drawPlayers()

	local i	= 0
	local count		= math.floor(windowStats.h / 35)
	local tcount	= 0
	if count < ourGame.playerCount then
		tcount		= math.floor(windowStats.h / 18)
		drawPlayersSmall(tcount)
	else
		drawPlayersBig(count)
	end

end

-- @TODO: Refactor this mess. D:
function drawPlayersSmall(count)
	local i = 0
	for _, pname in pairs(ourGame.internalPlayers) do
		if i < count then
			local y			= 3 + i * 18
			local player	= ourGame.players[pname]
			local pdata		= ourGame.playerData[pname]
			local pEXP		= (pdata.dexp - pdata.thisLevelExp) / (pdata.nextLevelExp - pdata.thisLevelExp) * 100

			--love.graphics.setFont(fonts.big)
			local col		= 128
			if player.activityTimeout > 0 then
				col			= 128 + ((player.activityTimeout / Game.activityTimeout) * 72)
			end
			if player.activity > 0 then
				col			= 200 + math.min(55, player.activity)
			end
			if not player.isInChannel then
				col			= 70
			end

			love.graphics.setColor(col, col, col)
			love.graphics.print(pname, 3, y)
			love.graphics.setColor(0, 0, 0)
			love.graphics.rectangle("fill", 100, y, 265, 20)
			love.graphics.setColor(255, 255, 255)
			love.graphics.setFont(fonts.small)
			love.graphics.printf("Lv", 110, y, 150, "left")
			love.graphics.printf(string.format("%d", pdata.level)  , 110, y,  32, "right")
			love.graphics.printf(string.format("%d EXP", pdata.exp), 110, y, 115, "right")

			drawExpBar(230, y + 2, (400 - 240), (pdata.exp - pdata.thisLevelExp) / (pdata.nextLevelExp - pdata.thisLevelExp), 6, false)
		end
		i = i + 1
	end
end


function drawPlayersBig(count)
	local i = 0
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
			if not player.isInChannel then
				col			= 70
			end

			love.graphics.setColor(col, col, col)
			love.graphics.print(pname, 3, y + 8)
			love.graphics.setColor(0, 0, 0)
			love.graphics.rectangle("fill", 135, y, 265, 40)
			love.graphics.setColor(255, 255, 255)
			love.graphics.setFont(fonts.small)
			love.graphics.printf(string.format("Level %d", pdata.level), 140, y, 125, "left")
			love.graphics.printf(string.format("%d EXP", pdata.exp), 143, y, 250, "right")

			drawExpBar(140, y + 16, 250, (pdata.exp - pdata.thisLevelExp) / (pdata.nextLevelExp - pdata.thisLevelExp), nil, true)
		end
		i = i + 1
	end
end





function save()
	local x = love.filesystem.write(ourGame.channel ..".json", json.encode(ourGame.playerData))
	print("File written state: ", x)
end

function love.quit()
	save()
	return false
end

oldErrHand	= love.errhand
function love.errhand(msg)
	print("ERROR!!!", msg)
	print("Attempting to save file data...")
	save()
	print("Running original error handler now...")
	oldErrHand(msg)

end


function drawExpBar(x, y, _w, pct, _h, _thick)
	local h		= _h and _h or 8
	local t		= 1
	local w		= _w
	if _thick then
		t		= 2
		love.graphics.setLineWidth(2)
		love.graphics.setColor(255, 255, 255)
		love.graphics.rectangle("fill", x + t, y + t, pct * w, h - (2 - t))
		love.graphics.setColor(160, 120, 255)
		love.graphics.rectangle("line", x, y, w + 2, h + 2)
	else
		love.graphics.translate( 0.5, 0.5 )
		love.graphics.setColor(255, 255, 255)
		love.graphics.rectangle("fill", x + t + 1, y + t, pct * (w - 2), h - (2 - t))
		love.graphics.setColor(160, 120, 255)
		love.graphics.rectangle("line", x, y, w + 2, h + 2)
	end

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