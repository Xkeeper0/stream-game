
local Game	= {}

local json					= require("json")

Game.__index				= Game
Game.maxActivity			= 300
Game.activityTimeout		= 600
Game.expTickRate			= 1
Game.sortListUpdateRate		= 5

Game.durationBonus	= {
		{	time	=       0,	rate	=   1.00	},	-- Base rate
		{	time	=      60,	rate	=   1.00	},	-- 1 minute
		{	time	=     120,	rate	=   1.33	},	-- 2 minutes
		{	time	=     300,	rate	=   2.00	},	-- 5 minutes
		{	time	=     600,	rate	=   3.00	},	-- 10 minutes
		{	time	=    1800,	rate	=   4.50	},	-- 30 minutes
		{	time	=    3600,	rate	=   6.25	},	-- 1 hour
		{	time	=    7200,	rate	=   8.00	},	-- 2 hours
		{	time	=   86400,	rate	=  12.00	},	-- a full day (should not happen)
		{	time	= 9999999,	rate	=  55.00	}	-- forever (should NEVER happen)
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
		sortListUpdate	= Game.sortListUpdateRate,
		playerCount		= 0,
		}

	return setmetatable(ret, Game)

end



function Game:update(dt)

	self:runUpdates(dt)

	self.sortListUpdate	= self.sortListUpdate - dt
	if self.sortListUpdate < 0 then
		self.sortListUpdate	= self.sortListUpdate + Game.sortListUpdateRate
		self:updateInternalList()
	end

end



function Game:runUpdates(dt)

	local	needSortUpdate	= false

	for player, pdata in pairs(self.players) do
		if pdata.isInChannel then
			pdata.duration	= pdata.duration + dt
		end

		if pdata.activity then

			pdata.activity			= pdata.activity - dt

			if (self.players[player].activity) > 0 then
				-- Still "active"
				pdata.activeDuration	= pdata.activeDuration + dt
				pdata.activityTimeout	= Game.activityTimeout
				self:awardExp(player, self:getExpPerTick(pdata, dt))

			else
				-- Activity timed out
				pdata.activity			= 0
				pdata.activityTimeout	= pdata.activityTimeout - dt

				if pdata.activityTimeout < 0 then
					pdata.activeDuration	= 0
					pdata.activityTimeout	= 0
				end

			end

		end

	end

end



local function activitySorter(self)
	return function (p1, p2)

		local player1	= { activity = self.players[p1], data = self.playerData[p1] }
		local player2	= { activity = self.players[p2], data = self.playerData[p2] }

		if player1.activity.isInChannel and not player2.activity.isInChannel then
			-- P1 in channel, P2 is not
			return true

		elseif not player1.activity.isInChannel and player2.activity.isInChannel then
			-- P2 in channel, P1 is not
			return false

		elseif player1.activity.activityTimeout > 0 and player2.activity.activityTimeout <= 0 then
			-- P1 is active, P2 is not
			return true

		elseif player1.activity.activityTimeout <= 0 and player2.activity.activityTimeout > 0 then
			-- P2 is active, P1 is not
			return false

		else
			-- Highest EXP wins
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
			nextLevelExp	= Game.getLevelExp(1),
		}
	end

	if not self.players[player] then
		self.players[player]	= {
			isInChannel			= true,
			activity			= 0,
			activeDuration		= 0,
			activityTimeout		= 0,
			duration			= 0,
			}
	end
	sounds.join:play()
	print("Added player", player)
	addMessage(player .." joined!")
	self.sortListUpdate			= 0
end

-- On part, remove player from active-players list
function Game:removePlayer(player, channel)
	if (channel and channel ~= self.channel) then return end
	if self.players[player] then
		sounds.leave:play()
		addMessage(player .." left.")
		--self.players[player]	= nil

		self.players[player].isInChannel		= false
		self.players[player].activeDuration		= 0
		self.players[player].activityTimeout	= 0

	end
	self.sortListUpdate			= 0
end


function Game:playerChat(player, channel, message)
	print("Chat", channel, player, message)
	if (not self.players[player]) then
		print("Adding not-joined player ".. player .."!")
		self:addPlayer(player, channel)

	end
	print("Updating activity:", player)
	local starterBonus	= (self.players[player].activity < 1) and 10 or 0
	self.players[player].activity	= math.min(Game.maxActivity, self.players[player].activity + 60 + starterBonus)
	print("New activity:", self.players[player].activity)
	--self:updateInternalList()
	self.sortListUpdate			= 0

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



function Game.getDurationBonus(time)
	local last	= 0
	local i		= 1
	while (time >= Game.durationBonus[i + 1].time) do
		i	= i + 1
	end

	-- i = current level, i+1 = new one
	local timeThis	= (        time                   - Game.durationBonus[i].time)
	local timeTotal	= (Game.durationBonus[i + 1].time - Game.durationBonus[i].time)

	local timepct	= timeThis / timeTotal

	local bonus		= Game.durationBonus[i + 1].rate * (timepct) + Game.durationBonus[i].rate * (1 - timepct)

	return bonus

end


function Game:getExpPerTick(pdata, dt)
	local b	= Game.getDurationBonus(pdata.duration)

	local exp	= b * 
			(dt * self.expTickRate) * 
			(0.5 + math.log(math.max(1, pdata.activeDuration - 300)) / 3) *
			math.min(1, pdata.activity / 60)

	return math.max(0, exp)

end




return Game