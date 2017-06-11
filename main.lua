local settings		= require("settings")

local class			= require('middleclass')


package.path = package.path .. ";./?/init.lua"

local json		= require("json")
--local socket	= require("socket")
local irc		= require("irc")
local Game		= require("game")
local WebRequest	= require("luajit-request")

local ircserv	= nil
local ourGame	= nil
local fonts		= {}
local windowStats	= {}
local lastDt	= 0
local followers	= {}

sounds	= {}

local didThread = false
local followThread	= nil
local cFollowing	= love.thread.getChannel("following")
local cFollowingNew	= love.thread.getChannel("newFollowers")
local threadError	= nil

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
		--tprint(ourGame)
		for user, t in pairs(users.users) do
			print("Adding to game:", user)
			ourGame:addPlayer(user, channel)
			ourGame:updateFollowing(followers, user)
		end

		ircserv:hook("OnChat",
			function(u, c, m)
				local t = ourGame:playerChat(u.nick, c, m)
				if t then
					ourGame:updateFollowing(followers, u.nick)
				end
			end
			)


		ircserv:hook("OnJoin",
			function(u, c)
				ourGame:addPlayer(u.nick, c)
				ourGame:updateFollowing(followers, u.nick)
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
	fonts.number	= love.graphics.newImageFont("images/numbers.png", "0123456789 kEXPLv.")
	fonts.numbersm	= love.graphics.newImageFont("images/numbers-small.png", "0123456789.")
	fonts.stars		= love.graphics.newImageFont("images/starbadges.png", "0123456789ABCDEF")
	fonts.starnums	= love.graphics.newImageFont("images/starnumbers.png", " 0123456789dmy")
	sounds.levelup	= love.audio.newSource("sounds/levelup.ogg", "static")
	sounds.join		= love.audio.newSource("sounds/p-join.ogg", "static")
	sounds.leave	= love.audio.newSource("sounds/p-leave.ogg", "static")
	sounds.follower	= love.audio.newSource("sounds/new-follower.ogg", "static")

	local _a, _b, _c	= love.window.getMode()
	windowStats	= { w = _a, h = _b, f = _c }

	tprint(windowStats)

	-- if true then return end

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

	if not didThread then
		didThread		= true
		followThread	= love.thread.newThread("threads/getfollowers.lua")
		followThread:start()

	elseif cFollowing:getCount() > 0 and ourGame then
		print("Got initial follower update")
		local followerUpdate = json.decode(cFollowing:pop())
		ourGame:updateFollowing(followerUpdate)
		updateLocalFollowing(followerUpdate)

	elseif cFollowingNew:getCount() > 0 and ourGame then
		print("Got new follower update")
		local followerUpdate = json.decode(cFollowingNew:pop())
		ourGame:updateFollowing(followerUpdate)
		updateLocalFollowing(followerUpdate)
		for k,v in pairs(followerUpdate) do
			addMessage(k .." just followed!")
			sounds.follower:play()
		end
	else
		local xxx = followThread:getError()
		if xxx and not threadError then
			print("thread error :( ".. xxx)
			threadError	= xxx
		end
	end


end

function love.draw()

	if ourGame then
		drawPlayers()

	end

	drawMessages()

end



function updateLocalFollowing(newFollowers)
	for k,v in pairs(newFollowers) do
		followers[k]	= v
	end
end


function drawPlayers()

	local i	= 0
	local count		= math.floor(windowStats.h / 35)
	local tcount	= math.floor(windowStats.h / 18) - 2
	drawPlayersSmall(tcount)
end


function formatNumberK(n)
	if n < 1000000 then
		return tostring(math.floor(n))
	else
		n	= tostring(math.floor(n / 1000)) .."k"
		return n
	end
end

function drawPlayersSmall(count)
	local i = 0
	for _, pname in pairs(ourGame.internalPlayers) do
		if i < count then
			local y			= 6 + i * 18
			local player	= ourGame.players[pname]
			local pdata		= ourGame.playerData[pname]
			local pEXP		= (pdata.dexp - pdata.thisLevelExp) / (pdata.nextLevelExp - pdata.thisLevelExp) * 100

			--love.graphics.setFont(fonts.big)
			local col		= 255
			if not player.isInChannel then
				col			= 120
			end

			love.graphics.setFont(fonts.stars)
			love.graphics.print(string.format("%X", pdata.starLevel), 3, y - 6)
			love.graphics.setColor(255, 230, 120)
			love.graphics.setFont(fonts.starnums)
			love.graphics.print(string.format("%3s", pdata.starBadge), 7, y + 4)

			love.graphics.setFont(fonts.small)
			love.graphics.setColor(col, col, col)
			love.graphics.print(pname, 33, y)
			love.graphics.setColor(0, 0, 0)
			love.graphics.rectangle("fill", 135, y, 265, 20)
			love.graphics.setColor(col, col, col)
			love.graphics.setFont(fonts.number)
			love.graphics.print("Lv", 140, y + 3)
			love.graphics.printf(string.format("%d", pdata.level)  , 152, y + 3,  28, "right")
			love.graphics.printf(string.format("%s XP", formatNumberK(pdata.exp)), 156, y + 3, 102, "right")
			love.graphics.setFont(fonts.small)

			drawExpBar(260, y + 2, (400 - 270), (pdata.exp - pdata.thisLevelExp) / (pdata.nextLevelExp - pdata.thisLevelExp), 6, false, (col / 255))
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


function drawExpBar(x, y, _w, pct, _h, _thick, cmul)
	local h		= _h and _h or 8
	local t		= 1
	local w		= _w
	if _thick then
		t		= 2
		love.graphics.setLineWidth(2)
		love.graphics.setColor(255 * cmul, 255 * cmul, 255 * cmul)
		love.graphics.rectangle("fill", x + t, y + t, pct * w, h - (2 - t))
		love.graphics.setColor(160 * cmul, 120 * cmul, 255 * cmul)
		love.graphics.rectangle("line", x, y, w + 2, h + 2)
	else
		love.graphics.translate( 0.5, 0.5 )
		love.graphics.setColor(255 * cmul, 255 * cmul, 255 * cmul)
		love.graphics.rectangle("fill", x + t + 1, y + t, pct * (w - 2), h - (2 - t))
		love.graphics.setColor(160 * cmul, 120 * cmul, 255 * cmul)
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
