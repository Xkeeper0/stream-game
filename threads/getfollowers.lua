local json			= require("json");
local WebRequest	= require("luajit-request")
local settings		= require("settings")
local timer			= require("love.timer")

local channel		= love.thread.getChannel("following")
local channelNew	= love.thread.getChannel("newFollowers")

local followDataS	= love.filesystem.read(settings.achannel .."-followers.json")
local followerData	= { followers = {} }
local startCursor	= nil

if followDataS then
	followerData	= json.decode(followDataS)
	print("Pushing pre-loaded following list")
	channel:push(json.encode(followerData.followers))
	startCursor		= followerData.cursor
end


--local followData	= love.filesystem.write(settings.achannel ..".json", json.encode(ourGame.playerData))

-- Debug function to recursively print table contents
function tprint (tbl, indent)
	if not indent then indent = 0 end
	for k, v in pairs(tbl) do
		formatting = string.rep("    ", indent) .. k .. ": "
		if type(v) == "table" then
			print(formatting)
			tprint(v, indent+1)
		else
			print(formatting .. tostring(v))
		end
	end
end

function dateToEpoch(dateString)
    local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)"
    local xyear, xmonth, xday, xhour, xminute, xseconds = dateString:match(pattern)
    local convertedTimestamp = os.time({year = xyear, month = xmonth, day = xday, hour = xhour, min = xminute, sec = xseconds})
    return convertedTimestamp + settings.tzoffset
end



function getLevel(years, days)
	-- months: 0, 1, 2, 3, 6, 9
	-- years: 1, 2, 3, 4, 5, 6
	if years >=  6 then return 12 end;
	if years >=  5 then return 11 end;
	if years >=  4 then return 10 end;
	if years >=  3 then return 9 end;
	if years >=  2 then return 8 end;
	if years >=  1 then return 7 end;
	if days >= (30 * 9) then return 6 end;
	if days >= (30 * 6) then return 5 end;
	if days >= (30 * 3) then return 4 end;
	if days >= (30 * 2) then return 3 end;
	if days >= (30 * 1) then return 2 end;
	return 1;
end



function checkLength(startTime)
	local now		= os.time()
	local days		= 86400
	local years		= 86400 * 365
	local duration	= math.max(0, now - startTime)
	local yearcount	= math.floor(duration / years)
	local daycount	= math.floor((duration - (years * yearcount)) / days)
	local badge		= ""
	if yearcount >= 1 then
		badge		= string.format("%dy", yearcount)
	elseif daycount >= 30 then
		badge		= string.format("%dm", math.floor(daycount / 30))
	elseif daycount > 1 then
		badge		= string.format("%dd", daycount)
	end

	return yearcount, daycount, duration, badge
end



local function getFollowing(startCursor, notifyNew)
	print("running thread, starting with cursor ".. tostring(startCursor))
	local done			= false
	local cursor		= startCursor and ("&cursor=".. startCursor) or ""
	local total			= 0
	local newFollowers	= {}
	repeat

		local endpoint	= "channels/".. settings.achannel .."/follows?direction=asc&limit=100" .. cursor
		print("Request Endpoint: ".. endpoint)
		local response	= apiRequest(endpoint)
		local follows	= json.decode(response.body)
		local count		= 0

		for k,v in ipairs(follows.follows) do
			local epoch	= dateToEpoch(v.created_at)
			local durationY, durationD, duration, badge	= checkLength(epoch)
			local level	= getLevel(durationY, durationD)
			followerData.followers[v.user.name]	= { since = epoch, level = level, badge = badge }
			if notifyNew then
				print("***")
				print(string.format("*** NEW FOLLOWER! ", v.user.name))
				print("***")
				newFollowers[v.user.name]	= followerData.followers[v.user.name]
			end
			print(string.format("  %-30s - %12d seconds - %d years, %3d days - level %2d - badge: %s", v.user.name, duration, durationY, durationD, level, badge))
			count		= count + 1
		end

		total			= total + count
		print(string.format("added %d followers, %d / %d, cursor %s", count, total, follows._total, follows._cursor))

		if count == 0 then
			done = true
		else
			-- Cursor is empty if no results
			followerData.cursor	= follows._cursor
			cursor				= "&cursor=".. follows._cursor
			timer.sleep(.5)
		end

	until done

	print("Done doing follower updates")
	if total > 0 then
		print(tostring(total) .. " updates")
		if not notifyNew then
			print("Pushing initial following list")
			channel:push(json.encode(followerData.followers))
		elseif notifyNew then
			print("Pushing new followers only")
			channelNew:push(json.encode(newFollowers))
		end
		love.filesystem.write(settings.achannel .."-followers.json", json.encode(followerData))
	else
		print("No new followers, nothing to see here")
	end

	print("Done pushing updates")

	-- Return cursor so we know where to start next time
	return followerData.cursor

end


function apiRequest(endpoint, customHeaders)

	headers	= {
		['Client-ID']	= settings.clientid,
		['Accept']		= "application/vnd.twitchtv.v5+json",
		}

	if customHeaders then
		for k, v in pairs(customHeaders) do
			headers[k]	= v
		end
	end

	local response	= WebRequest.send(
			"https://api.twitch.tv/kraken/" .. endpoint,
			{ headers = headers }
		)

	return response

end

local checkForNew	= false
while true do
	print("Running follower check now")
	startCursor			= getFollowing(startCursor, checkForNew)
	checkForNew			= true
	print("Follower check: Sleeping for a minute now")
	love.timer.sleep(60)
end
