-- license:BSD-3-Clause
-- copyright-holders:Doozer

local exports = {}
exports.name = "display_frameinfo"
exports.version = "0.1"
exports.description = "Display frame information"
exports.license = "BSD 3-Clause"
exports.author = { name = "Doozer" }

local display_frameinfo = exports

local visibility_at_start = false -- by default the plugin is activated together with the MAME speed/frame skip information screen by using the F11 key
local log_console = false -- print frame speed changes to the console/terminal 
local font_width = 6 -- default front width
local resolution_change_framecounter = 300 -- define how ofter the xrandr resolution is checked

-- global variables
local screen
local render
local last_percent = 0
local xrandr 
local xrandr_init = false
local last_resolution = ""

function Exec(command) -- execute command and retrurn the output as a line buffer
	local buffer = {}
	local tmpfile = '/tmp/display_frameinfo.exec.txt' -- /tmp must be writable 
	os.execute(command..' > '..tmpfile) -- execute command
	local f = io.open(tmpfile) 
	if not f then return buffer end -- if the output file does not exist return an empty buffer
	local l = 1
	for line in f:lines() do -- copy lines to the buffer
		buffer[l] = line
		l = l + 1
	end
	f:close()
	return buffer
end

function display_frameinfo.startplugin()

	local start_time = 0        -- start time

	local offset_x_text = 10 -- offset the text from the left side of the screen
	local offset_value = 110 -- offset the value/parameter to indent them 
	local offset_y = 10 -- offset the text from the top screen
	local offset_y_line = 10 -- offset value for new line
	local offset_y_paragraph = 15 -- offset value for new paragraph

	local info = string.format("%s v%s", exports.name, exports.version)
	print (info) -- display plugin information

	emu.register_start(function() -- get the screen and rederer at plugin start
		screen = manager.machine.screens:at(1)
		render = manager.machine.render.targets:at(1)

	end)

	emu.register_frame_done(function()

		if ( (visibility_at_start ~= manager.ui.show_fps) and screen ) then -- check if frame information screen msut be displayed
			local curtime = manager.machine.time -- capture time information

			if ( start_time == 0 ) then
				start_time = curtime -- set startime if not set
			end

			-- calculate the frame time
			local sec_start = curtime.seconds
			local usec_start = (sec_start * 1000000) + curtime.usec
			local elapsed = curtime - start_time
			local sec_elapsed = elapsed.seconds
			local usec_elapsed = (sec_elapsed * 1000000) + elapsed.usec
			start_time = curtime

			-- set initial cursor position
			local pos_y = 0
			local str = ""

			-- local offset_x_value = math.ceil((screen.width - offset_x_text*2)/6) * offset_value
			local offset_x_value = math.ceil(screen.width/320) * offset_value
			-- local offset_x_value = offset_x_text + font_width * offset_value
			-- local total_col =  math.ceil((screen.width - offset_x_text*2)/font_width)
			if ( screen.width <= 256 ) then
				total_col =  math.ceil((screen.width - offset_x_text*2)/font_width)
			else
				total_col = 50
			end

			-- display a darker box behind the text
			screen:draw_box(5, 5, screen.width - 5, screen.height - 5, 0x90223344, 0x90223344)
			-- display the plugin information
			screen:draw_text(offset_x_text, offset_y + pos_y, info)

			-- display the speed information
			pos_y = pos_y + offset_y_paragraph
			screen:draw_text(offset_x_text, offset_y + pos_y, "Speed:")
			local video = manager.machine.video
			local percent = math.floor(manager.machine.video.speed_percent*1000)
			str = string.format("%.3f %%", manager.machine.video.speed_percent * 100)
			screen:draw_text(offset_x_value , offset_y + pos_y, str)
			if ( log_console and percent ~= last_percent ) then
				print (string.format("%10d: %s", screen:frame_number(), str))
				last_percent = percent
			end

			-- display the frame counter and frame time
			pos_y = pos_y + offset_y_line
			screen:draw_text(offset_x_text, offset_y + pos_y, "Frame counter:")
			screen:draw_text(offset_x_value , offset_y + pos_y, string.format("%d (%.3f ms)", screen:frame_number(), usec_elapsed / 1000))

			-- display the current resolution
			pos_y = pos_y + offset_y_line
			screen:draw_text(offset_x_text, offset_y + pos_y, "Resolution:")
			screen:draw_text(offset_x_value, offset_y + pos_y, string.format("%d x %d ", render.width, render.height))

			-- use 8 characters from A to H to represent the frame change, cycle beween them at every new frame (usefull to check latency when using multiple monitors)
			pos_y = pos_y + offset_y_line
			screen:draw_text(offset_x_text, offset_y + pos_y, "Frame loop:")
			str = ""
			local scan_id = screen:frame_number() & 0x7
			for i = 0,7,1 do
				if ( scan_id == i) then
					str = string.format("%s%s ", str, string.char(65 + i))
				else
					str = string.format("%s%s ", str, "_")
				end
			end
			screen:draw_text(offset_x_value, offset_y + pos_y, str)

			-- display all the input registers for the running game
			pos_y = pos_y + offset_y_line
			str = ""
			screen:draw_text(offset_x_text, offset_y + pos_y, "Inputs:")
			local idx = 0
			for tag, port in pairs(manager.machine.ioport.ports) do
				if ( idx > 0 and idx % 8 == 0 ) then
					screen:draw_text(offset_x_value, offset_y + pos_y, str)
					pos_y = pos_y + 10
					str = ""
				end
				idx = idx + 1
				str = string.format("%s%02X ", str, port:read())
			end
			screen:draw_text(offset_x_value, offset_y + pos_y, str)

			-- display the game information
			pos_y = pos_y + offset_y_paragraph
			screen:draw_text(offset_x_text, offset_y + pos_y, "________________")
			screen:draw_text(offset_x_text, offset_y + pos_y - 2, "Game information")

			-- game resolution
			pos_y = pos_y + offset_y_line
			screen:draw_text(offset_x_text, offset_y + pos_y, "Resolution:")
			screen:draw_text(offset_x_value, offset_y + pos_y, string.format("%d x %d ", screen.width, screen.height))

			-- game horizontal refresh rate
			pos_y = pos_y + offset_y_line
			screen:draw_text(offset_x_text, offset_y + pos_y, "Horizontal rate:")
			screen:draw_text(offset_x_value, offset_y + pos_y, string.format("%.3f kHz", 1/(screen.scan_period * 1000)))

			-- game vertical refresh rate
			pos_y = pos_y + offset_y_line
			screen:draw_text(offset_x_text, offset_y + pos_y, "Vertical rate:")
			screen:draw_text(offset_x_value, offset_y + pos_y, string.format("%.3f Hz", screen.refresh))

			-- game frame time
			pos_y = pos_y + offset_y_line
			screen:draw_text(offset_x_text, offset_y + pos_y, "Frame time:")
			screen:draw_text(offset_x_value, offset_y + pos_y, string.format("%.3f ms", screen.frame_period * 1000))

			-- display the xrandr information (ony available if Xorg is used and /tmp is writable)
			pos_y = pos_y + offset_y_paragraph
			screen:draw_text(offset_x_text, offset_y + pos_y, "__________________")
			screen:draw_text(offset_x_text, offset_y + pos_y - 2, "Xrandr information")

			-- capture the current Xorg resolution and check every 300 frames if the resolution have changed
			if ( (screen:frame_number()%resolution_change_framecounter == 0 or not xrandr_init) and last_resolution ~= string.format("%dx%d@%f", screen.width, screen.height, screen.scan_period)) then
				xrandr = Exec("DISPLAY=:0 xrandr --verbose > /tmp/xrandr.output; (grep ' connected' /tmp/xrandr.output | sed 's+ \\((0[^)\\]*)\\).*\\| (.*+\\1+' ; grep '*' -A 2 /tmp/xrandr.output | sed 's+) +)\\n+' | sed 's+ total+\\ntotal+' | sed 's+ *\\(.\\{,"..total_col.."\\}\\)+\\1\\n+g' | grep -v '^$')")
				last_resolution = string.format("%dx%d@%f", screen.width, screen.height, screen.scan_period)
				xrandr_init = true
			end
			-- only display xrandr information if available
			if ( xrandr_init ) then
				for p,l in pairs(xrandr) do
					pos_y = pos_y + offset_y_line
					screen:draw_text(offset_x_text, offset_y + pos_y, l)
				end
			end

		end

	end)

end

return exports
