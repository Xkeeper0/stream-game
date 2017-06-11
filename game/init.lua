
local Game	= {}

local json					= require("json")

Game.__index				= Game
Game.expTickRate			= 1
Game.expBonusRate			= {
	[ 0]	= 0.900,	-- Non-follower
	[ 1]	= 1.000,	-- New follower
	[ 2]	= 1.250,	-- 1 month
	[ 3]	= 1.375,	-- 2 months
	[ 4]	= 1.500,	-- 3 months
	[ 5]	= 1.700,	-- 6 months
	[ 6]	= 1.900,	-- 9 months
	[ 7]	= 2.000,	-- 1 year
	[ 8]	= 2.100,	-- 2 years
	[ 9]	= 2.150,	-- 3 years
	[10]	= 2.275,	-- 4 years
	[11]	= 2.400,	-- 5 years
	[12]	= 2.500,	-- 6 years
	}

function Game.start(channel)


	local playerData	= {}
	if (love.filesystem.exists(channel ..".json")) then
		playerData		= json.decode(love.filesystem.read(channel ..".json"))
	end

	local ret	= {
		channel			= channel,
		players			= {},
		playerData		= playerData,		-- All players + data
		nextUpdate		= Game.updateTime,
		internalPlayers	= {},
		playerCount		= 0,
		}

	return setmetatable(ret, Game)

end



function Game:update(dt)

	self:runUpdates(dt)

end


function Game:updateFollowing(followers, playerName)
	if not playerName then
		for k, v in pairs(self.playerData) do
			if followers[k]	then
				print(string.format("Updating %s as having starlevel %d and badge %s!", k, followers[k].level, followers[k].badge))
				self.playerData[k].starLevel	= followers[k].level
				self.playerData[k].starBadge	= followers[k].badge
			end
		end
	else
		if followers[playerName] and self.playerData[playerName] then
			self.playerData[playerName].starLevel	= followers[playerName].level
			self.playerData[playerName].starBadge	= followers[playerName].badge
		end
	end
end


function Game:runUpdates(dt)

	-- Award EXP per tick to each player who is active
	for player, pdata in pairs(self.players) do
		if pdata.isInChannel then
			self:awardExp(player, self:getExpPerTick(self.playerData[player], dt))
		end

	end
end



local function activitySorter(self)
	return function (p1, p2)

		local player1	= { activity = self.players[p1], data = self.playerData[p1] }
		local player2	= { activity = self.players[p2], data = self.playerData[p2] }

		-- People still in the channel sort first
		if player1.activity.isInChannel and not player2.activity.isInChannel then
			-- P1 in channel, P2 is not
			return true

		elseif not player1.activity.isInChannel and player2.activity.isInChannel then
			-- P2 in channel, P1 is not
			return false

		else
			-- Otherwise, sort by EXP
			return player1.data.exp > player2.data.exp
		end
	end
end


function Game:updateInternalList()
	local plist	= {}
	local count	= 0
	for k, v in pairs(self.players) do
		count	= count + 1
		plist[count] = k
	end

	local sorter		= activitySorter(self)
	table.sort(plist, sorter)
	self.internalPlayers	= plist
	self.playerCount		= count

end


-- On join, add player to active-players list
function Game:addPlayer(player, channel)
	if (channel ~= self.channel) then return end
	if (not self.playerData[player]) then
		self.playerData[player]	= {
			level			= 1,
			exp				= 0,
			dexp			= 0,
			thisLevelExp	= 0,
			starLevel		= 0,
			starBadge		= "",
			nextLevelExp	= Game.getLevelExp(1),
		}

	elseif (self.players[player] and not self.players[player].isInChannel) then
		print("Readded disappeared player", player)
		self.players[player].isInChannel	= true

	end

	if not self.players[player] then
		self.players[player]	= {
			isInChannel			= true,
			}
	end
	sounds.join:play()
	print("Added player", player)
	addMessage(player .." joined!")
	self:updateInternalList()
end

-- On part, remove player from active-players list
function Game:removePlayer(player, channel)
	if (channel and channel ~= self.channel) then return end
	if self.players[player] then
		sounds.leave:play()
		addMessage(player .." left.")
		--self.players[player]	= nil

		self.players[player].isInChannel		= false

	end
	self:updateInternalList()
end


function Game:playerChat(player, channel, message)
	print("Chat", channel, player, message)
	if (not self.players[player] or not self.players[player].isInChannel) then
		print("Adding not-joined player ".. player .."!")
		self:addPlayer(player, channel)
		return true
	end
	return false
end



function Game:awardExp(player, exp)

	local p		= self.playerData[player]
	local cl	= p.level
	local ce	= p.exp
	local cr	= p.nextLevelExp
	p.exp		= p.exp + exp
	p.dexp		= math.floor(p.exp)
	if math.floor(p.exp) >= cr then
		print("Level up!", player, cl + 1)
		sounds.levelup:play()
		p.level	= p.level + 1
		p.thisLevelExp	= cr
		p.nextLevelExp	= Game.getLevelExp(cl + 1)
		addMessage(string.format("%s is now level %d!", player, p.level))
	end


end


function Game.getLevelExp(level)
	return math.floor(100 * level + (5 * (level - 1) ^ 3) / 3)
end

function Game:getExpPerTick(pdata, dt)
	local bonus	= 0.0
	if pdata.starLevel then
		bonus = self.expBonusRate[pdata.starLevel]
	end
	local exp	= (dt * self.expTickRate) * bonus

	return math.max(0, exp)

end




return Game
