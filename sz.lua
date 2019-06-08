local M = {}

local cpu = manager:machine().devices[":maincpu"]
local mem = cpu.spaces["program"]
local ioport = manager:machine():ioport()
local in0 = ioport.ports[":P1HANDLE"]
local in1 = ioport.ports[":P3HANDLE"]

M.CoinIn = { in0 = in0, field = in0.fields["Coin 1"] }
M.Start1 = { in0 = in0, field = in0.fields["1 Player Start"] }
M.Fire   = { in1 = in1, field = in1.fields["P1 Button 1"] }
M.Up     = { in1 = in1, field = in1.fields["P1 Aim Up"] }
M.Down   = { in1 = in1, field = in1.fields["P1 Aim Down"] }
M.Left   = { in1 = in1, field = in1.fields["P1 Aim Left"] }
M.Right  = { in1 = in1, field = in1.fields["P1 Aim Right"] }

-- Main game states
local STATE_START_UP	  = 0
local STATE_COIN_DOWN     = 1
local STATE_COIN_UP		  = 2
local STATE_PRESS_START   = 3
local STATE_RELEASE_START = 4
local STATE_PLAY_GAME     = 5

-- Play state substates
local SUBSTATE_LOOK_FOR_TARGET	= 1
local SUBSTATE_BUTTONS_DOWN		= 2
local SUBSTATE_BUTTONS_UP		= 3
local SUBSTATE_FIRE_BREAK		= 4
local SUBSTATE_FIRE_AGAIN		= 5
local SUBSTATE_FIRE_UP			= 6
local SUBSTATE_WAIT_FOR_FIRE_ON = 7
local SUBSTATE_WAIT_FOR_FIRE_OFF= 8

-- Moves "enum"
local UP    = 1
local DOWN	= 2
local LEFT  = 4
local RIGHT = 8

M.state = STATE_START_UP
M.substate = SUBSTATE_LOOK_FOR_TARGET
M.counter = 0
M.lastMove = 0
M.fireDown = false

-- Check direction for laser in requested state
function M.checkLaser(direction, state)
	local matches = 0
	compare = 0
	
	if direction == UP then
		if state == 0 then
			compare = 0
		else
			compare = 0xC003
		end
		
		if mem:read_u16(0x4617) == compare then
			matches = matches + 1
		end
		if mem:read_u16(0x4B67) == compare then
			matches = matches + 1
		end
		if mem:read_u16(0x50B7) == compare then
			matches = matches + 1
		end
	elseif direction == RIGHT then
		if state == 0 then
			compare = 0
		else
			compare = 0xFFFF
		end
		if mem:read_u16(0x5ECE) == compare then
			matches = matches + 1
		end
		if mem:read_u16(0x5EDB) == compare then
			matches = matches + 1
		end
		if mem:read_u16(0x5EE8) == compare then
			matches = matches + 1
		end
	elseif direction == DOWN then
		if state == 0 then
			compare = 0
		else
			compare = 0xC003
		end
	
		if mem:read_u16(0x6697) == compare then
			matches = matches + 1
		end
		if mem:read_u16(0x6C37) == compare then
			matches = matches + 1
		end
		if mem:read_u16(0x71D7) == compare then
			matches = matches + 1
		end
	elseif direction == LEFT then
		if state == 0 then
			compare = 0
		else
			compare = 0xFFFF
		end
	
		if mem:read_u16(0x5EA4) == compare then
			matches = matches + 1
		end
		if mem:read_u16(0x5EB2) == compare then
			matches = matches + 1
		end
		if mem:read_u16(0x5EC0) == compare then
			matches = matches + 1
		end
	else
		return true
	end
	
	if state == 1 then
		if matches >= 2 then
			return true
		end
	else
		if matches >= 2 then
			return true
		end
	end
	
	return false
end
-- We have "lanes" that we use to check for enemies.  The starfield is randomly generated, and can put stars in our way.
function M.clearStars()
	-- Left and Right are easy
	for i = 0,3
	do 	
		mem:write_u64(0x5EA0 + (i * 8), 0)
		mem:write_u64(0x5ECE + (i * 8), 0)
	end
	
	-- Now, do Up
	for i = 0x50B7,0x4027,-0x50
	do 		
		mem:write_u16(i, 0)
	end
	
	-- And lastly, do Down
	for i = 0x6697,0x7E57,0x50
	do 
		mem:write_u16(i, 0)
	end	
end
-- Check to the LEFT of the base for something to shoot (Higher numbers are closer to the base)
function M.checkLeft()
	retVal = -1
	
	-- Loop through in 8 byte chunks
	for i = 3,0,-1
	do
		test = mem:read_u64(0x5EA0 + (i * 8))
		if test ~= 0 then			
			if (test & 0xFF00000000000000) ~= 0 then
				retVal = 32 - (i * 8)
			elseif (test & 0xFF000000000000) ~= 0 then
				retVal = 31 - (i * 8)
			elseif (test & 0xFF0000000000) ~= 0 then
				retVal = 30 - (i * 8)
			elseif (test & 0xFF00000000) ~= 0 then
				retVal = 29 - (i * 8)
			elseif (test & 0xFF000000) ~= 0 then
				retVal = 28 - (i * 8)
			elseif (test & 0xFF0000) ~= 0 then
				retVal = 27 - (i * 8)
			elseif (test & 0xFF00) ~= 0 then
				retVal = 26 - (i * 8)
			elseif (test & 0xFF) ~= 0 then
				retVal = 25 - (i * 8)
			end
		end
	end
	
	return retVal
end
-- Check to the RIGHT of the base for something to shoot (Lower numbers are closer to the base)
function M.checkRight()
	retVal = -1

	-- Read all the bytes via U64
	for i = 0,3
	do 
		test = mem:read_u64(0x5ECE + (i * 8))
		if test ~= 0 then
			if (test & 0xFF) ~= 0 then
				return 1 + (i * 8)
			elseif (test & 0xFF00) ~= 0 then
				return 2 + (i * 8)
			elseif (test & 0xFF0000) ~= 0 then
				return 3 + (i * 8)
			elseif (test & 0xFF000000) ~= 0 then
				return 4 + (i * 8)
			elseif (test & 0xFF00000000) ~= 0 then
				return 5 + (i * 8)
			elseif (test & 0xFF0000000000) ~= 0 then
				return 6 + (i * 8)				
			elseif (test & 0xFF000000000000) ~= 0 then
				return 7 + (i * 8)
			elseif (test & 0xFF00000000000000) ~= 0 then
				return 8 + (i * 8)
			end			
		end
	end

	-- If we've made it THIS far, then there's nothing there
	return -1
end
-- Check ABOVE the base for something to shoot (Higher numbers are closer to the base)
function M.checkUp()

	-- There are 26 characters ABOVE the base, and 38 below
	retVal = 1
	
	for i = 0x50B7,0x4027,-0x50
	do 		
		if (mem:read_u16(i) ~= 0) and (mem:read_u16(i) ~= 0xC003) then
			return retVal
		else		
			retVal = retVal + 1
		end
	end

	return -1
end
-- Check BELOW the base for something to shoot (Lower numbers are closer to the base)
function M.checkDown()

	retVal = 1

	for i = 0x6697,0x7E57,0x50
	do 
		if (mem:read_u16(i) ~= 0) and (mem:read_u16(i) ~= 0xC003) then
			return retVal
		else
			retVal = retVal + 1
		end
	end

	return -1
end
-- Check all 4 directions, and return the direction we should fire
function M.whichDirection()
	lowest = 75
	direction = 0
	
	temp = M.checkUp()
	if (temp ~= -1) and (M.lastMove ~= UP) then
		lowest = temp
		direction = UP
	end
	
	temp = M.checkRight()
	if (temp ~= -1) and (temp < lowest) and (M.lastMove ~= RIGHT) then
		lowest = temp
		direction = RIGHT
	end
	
	temp = M.checkDown()
	if (temp ~= -1) and (temp < lowest) and (M.lastMove ~= DOWN) then
		lowest = temp
		direction = DOWN
	end
	
	temp = M.checkLeft()
	if (temp ~= -1) and (temp < lowest) and (M.lastMove ~= LEFT) then
		lowest = temp
		direction = LEFT
	end
	
	return direction
end
-- function called every frame
function M.updateMem()

	M.counter = M.counter + 1

	if M.state == STATE_START_UP then
		if M.counter > 70 then
			M.state = STATE_COIN_DOWN
			return
		end
	elseif M.state == STATE_COIN_DOWN then
		-- Drop a coin in
		M.CoinIn.field:set_value(1)
		M.state = STATE_COIN_UP
		M.counter = 0
	elseif M.state == STATE_COIN_UP then
		if M.counter > 10 then
			M.CoinIn.field:set_value(0)
			M.state = STATE_PRESS_START
		end
	elseif M.state == STATE_PRESS_START then
		-- Wait for the credit to show up
		if mem:read_u8(0xD160) ~= 0x00 then
			-- Press 1-player start button
			M.Start1.field:set_value(1)
			M.state = STATE_RELEASE_START
			M.counter = 0
		end
	elseif M.state == STATE_RELEASE_START then
		if M.counter == 350 then
			-- Release 1-player start button
			M.Start1.field:set_value(0)
			M.clearStars()
			M.state = STATE_PLAY_GAME
			M.substate = SUBSTATE_LOOK_FOR_TARGET
			M.counter = 0
		end
	elseif M.state == STATE_PLAY_GAME then
		if M.substate == SUBSTATE_LOOK_FOR_TARGET then
			direction = M.whichDirection()
			if direction ~= 0 then
				if direction == UP then
					M.Up.field:set_value(1)
					M.lastMove = UP
				elseif direction == RIGHT then
					M.Right.field:set_value(1)
					M.lastMove = RIGHT
				elseif direction == DOWN then
					M.Down.field:set_value(1)
					M.lastMove = DOWN				
				elseif direction == LEFT then
					M.Left.field:set_value(1)
					M.lastMove = LEFT
				end
			end

			if M.lastMove == 0 then
				return
			end
			
			M.Fire.field:set_value(1)
			M.fireDown = true
			M.counter = 0
			M.substate = SUBSTATE_WAIT_FOR_FIRE_ON
			return
		elseif M.substate == SUBSTATE_WAIT_FOR_FIRE_ON then
			if M.fireDown ~= true then
				M.Fire.field:set_value(1)
				M.fireDown = true
			else
				M.Fire.field:set_value(0)
				M.fireDown = false
			end				

			-- Then, wait for the laser beam to appear
			if M.checkLaser(M.lastMove, 1) == true then
				M.Fire.field:set_value(0)
				M.fireDown = false
				
				if M.lastMove == UP then
					M.Up.field:set_value(0)
				elseif M.lastMove == RIGHT then
					M.Right.field:set_value(0)
				elseif M.lastMove == DOWN then
					M.Down.field:set_value(0)
				elseif M.lastMove == LEFT then
					M.Left.field:set_value(0)
				end
				
				M.substate = SUBSTATE_WAIT_FOR_FIRE_OFF
			end
		elseif M.substate == SUBSTATE_WAIT_FOR_FIRE_OFF then
			if M.checkLaser(M.lastMove, 0) == true then
				M.substate = SUBSTATE_LOOK_FOR_TARGET				
			end
		else
			print("Unknown substate " .. M.substate)
			emu.pause()
		end
	end
	
	return
end

-- start game
function M.start()	
    -- register update loop callback function
    emu.register_frame_done(M.updateMem, "frame")	
end

M.start()

return M
