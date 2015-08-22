
local Game	= {}

local json					= require("json")

Game.__index				= Game
Game.maxActivity			= 150
Game.activityTimeout		= 300
Game.expTickRate			= 1

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
		internalPlayers	= {}
		}

	return setmetatable(ret, Game)

end



function Game:update(dt)

	--self.updateTime	= self.updateTime - dt
	--while (self.updateTime < 0) do
	--	self.updateTime	= self.updateTime + Game.updateTime
		self:runUpdates(dt)
	--end
end



function Game:runUpdates(dt)

	for player, pdata in pairs(self.players) do
		pdata.duration	= pdata.duration + dt
		if pdata.activity then
			pdata.activity			= pdata.activity - dt
			if (self.players[player].activity) > 0 then
				pdata.activeDuration	= pdata.activeDuration + dt
				pdata.activityTimeout	= Game.activityTimeout
				-- Replace with "giveEXP" thing to handle flashy stuff
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

		local skey1	= (self.players[p1].activity * 1000000000) + self.players[p1].activityTimeout * 100000000 + self.players[p1].duration * 1000 + self.playerData[p1].exp
		local skey2	= (self.players[p2].activity * 1000000000) + self.players[p2].activityTimeout * 100000000 + self.players[p2].duration * 1000 + self.playerData[p2].exp

		return skey1 > skey2
	end
end

function Game:updateInternalList()
	local plist	= {}
	for k, v in pairs(self.players) do
		table.insert(plist, k)
	end

	local sorter		= activitySorter(self)
	table.sort(plist, sorter)
	self.internalPlayers	= plist

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

	self.players[player]	= {
		activity			= 0,
		activeDuration		= 0,
		activityTimeout		= 0,
		duration			= 0,
		}
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
		self.players[player]	= nil
	end
	self:updateInternalList()
end


function Game:playerChat(player, channel, message)
	print("Chat", channel, player, message)
	if (not self.players[player]) then 
		print("Unknown player ".. player .."!")
		return
	end
	print("Updating activity:", player)
	self.players[player].activity	= math.min(Game.maxActivity, self.players[player].activity + 60)
	print("New activity:", self.players[player].activity)
	self:updateInternalList()

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
	local d	= pdata.duration
	local b	= 0
	if d < 0 then
		b = false
	elseif d < 60 then
		b = 1
	elseif d < 60 then
		b = 2
	elseif d < 300 then
		b = 3
	elseif d < 600 then
		b = 4
	elseif d < 1800 then
		b = 5
	else
		b = 7
	end


	local exp	= b * 
			(dt * self.expTickRate) * 
			(0.5 + math.log(math.max(1, pdata.activeDuration - 300)) / 3) *
			math.min(1, pdata.activity / 60)

	--print(exp, (dt * self.expTickRate), (0.5 + math.log(pdata.activeDuration) / 3), math.min(1, pdata.activity / 60))
	return math.max(0, exp)

end




return Game