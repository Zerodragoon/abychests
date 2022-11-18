_addon.name     = 'abychests'
_addon.author   = 'Zerodragoon'
_addon.version  = '1.0'
_addon.commands = {'abc', 'abychests'}

require('logger')
require('coroutine')
require('pack')
inspect = require('inspect')
packets = require('packets')
res = require('resources')
config = require('config')

local commands = {}
local choice = {}
local box_name = 'Sturdy Pyxis'
local key_id = 2490
local open_chests = false
local has_keys = false
local debug_mode = false

local box_types = {
    'blue',
	'red',
	'gold',
	'big_gold'
}

local light_types = {
    'pearlescent',
	'azure',
	'ruby',
	'amber',
	'golden',
	'silvery',
	'ebon'
}

local settings = T{
    types = L{'blue',},
	red_lights = L{'ebon',},
	gold_items = L{}
}

local box_queue
local item_queue

local last_clear_time

local save_file

local clear_chest
local previous_chest
local previous_chest_attempts = 0

local function queue()
  local out = {}
  local first, last = 0, -1
  out.push = function(item)
    last = last + 1
    out[last] = item
  end
  out.pop = function()
    if first <= last then
      local value = out[first]
      out[first] = nil
      first = first + 1
      return value
    end
  end
  out.iterator = function()
    return function()
      return out.pop()
    end
  end
  setmetatable(out, {
    __len = function()
      return (last-first+1)
    end,
  })
  return out
end

do
	math.randomseed(os.time())
	box_queue = queue()
	item_queue = queue()
    local file_path = windower.addon_path..'data/settings.lua'
    local table_tostring

    table_tostring = function(tab, padding) 
        local str = ''
        for k, v in pairs(tab) do
            if class(v) == 'List' then
                str = str .. '':rpad(' ', padding) .. '["%s"] = L{':format(k) .. table_tostring(v, padding+4) .. '},\n'
            elseif class(v) == 'Table' then
                str = str .. '':rpad(' ', padding) .. '["%s"] = T{\n':format(k) .. table_tostring(v, padding+4) .. '':rpad(' ', padding) .. '},\n'
            elseif class(v) == 'table' then
                str = str .. '':rpad(' ', padding) .. '["%s"] = {\n':format(k) .. table_tostring(v, padding+4) .. '':rpad(' ', padding) .. '},\n'
            elseif class(v) == 'string' then
                str = str .. '"%s",':format(v)
            end
        end
        return str
    end

    save_file = function()
        local make_file = io.open(file_path, 'w')
        
        local str = table_tostring(settings, 4)

        make_file:write('return {\n' .. str .. '}\n')
        make_file:close()
    end

    if windower.file_exists(file_path) then
        settings = settings:update(dofile(file_path))
    else
        save_file()
    end
end

local function escape()
	windower.send_command('setkey escape down')
	coroutine.sleep(.2)
	windower.send_command('setkey escape up')
	coroutine.sleep(1)
end

local function has_value_table (tab, val)
    for index, value in pairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

local function enabled()
	local enabled = open_chests and has_keys
	return enabled
end

local function find_key() 
	local inventory = windower.ffxi.get_items(0)

	for index = 1, inventory.max do
		local is_key = inventory[index].id == key_id
		
		if is_key then
			return inventory[index]
		end
	end
end

local function user_has_keys()
	local temp_has_keys = false
	
	local inventory = windower.ffxi.get_items(0)
	
	for index = 1, inventory.max do
		local is_key = inventory[index].id == key_id
		
		if is_key then
			temp_has_keys = true
			break
		end
	end
	
	if debug_mode then
		windower.add_to_chat(1,'User has keys '..tostring(temp_has_keys)..'')                           
	end

	has_keys = temp_has_keys
	
	return temp_has_keys
end

local function find_box(box_id)
    local mob = windower.ffxi.get_mob_by_id(box_id)
	if mob and (mob.name == box_name) and (math.sqrt(mob.distance) < 6) then
		return mob
	end
end

local function process_box_queue(id, data)
	if enabled() then
		local box = box_queue.pop();
		if box then
			local npc = find_box(box)
			local key = find_key()
			
			if npc then 
				local random = math.random(1,2)
				coroutine.sleep(1 + random)
							
				if key then
					local menu_item = 'C4I11C10HI':pack(0x36,0x20,0x00,0x00,npc.id,
					1,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
					key.slot,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
					npc.index,1)
					windower.packets.inject_outgoing(0x36, menu_item)
					
					item_queue.push(npc.id)
				end
			end
		end

		coroutine.schedule(process_box_queue, .2)
	end
end

local function process_item_queue(id, data)
    if enabled() and not settings.gold_items:empty() then
		local player = windower.ffxi.get_player()

		if player.status == 0 then
			local skip_next = false
			if previous_chest then
				local npc = find_box(previous_chest)

				if npc then
					coroutine.sleep(5)

					skip_next = true
					previous_chest_attempts = previous_chest_attempts + 1
					
					if previous_chest_attempts > 5 then
						clear_chest = true
						previous_chest = nil
					end

					local p = packets.new('outgoing', 0x1a, {
						['Target'] = npc.id,
						['Target Index'] = npc.index,
					})
					packets.inject(p)
					
					coroutine.schedule(escape, 1)
				else
					previous_chest = nil
					previous_chest_attempts = 0
				end
			end

			if not skip_next then
				local box = item_queue.pop();
				if box then
					local npc = find_box(box)
					local key = find_key()
					
					if npc then 
						local p = packets.new('outgoing', 0x1a, {
							['Target'] = npc.id,
							['Target Index'] = npc.index,
						})
						packets.inject(p)
						
						coroutine.schedule(escape, 1)

						previous_chest = box
						previous_chest_attempts = 0
					end
				end
			end
		end
		coroutine.schedule(process_item_queue, 10)
    end
end

local function obtain_item(id, data)
    if (id == 0x5b) and enabled() and not settings.gold_items:empty() then        
        local p = packets.parse('outgoing', data)
		local optionIndexBoolean = p['Option Index'] == 111
		local npc = windower.ffxi.get_mob_by_id(p['Target'])
        if npc and (npc.name == box_name) and (not optionIndexBoolean) then
			
			if clear_chest then
				p['Option Index'] = 2
				p['_unknown1'] = 0
				clear_chest = false
			else 
				p['Option Index'] = 1
				p['_unknown1'] = 1
			end
			
			return packets.build(p)
		end
    end
end

local function observe_box_spawn(id, data)
    if (id == 0x38) then
        local p = packets.parse('incoming', data)
        local npc = find_box(p['Mob'])
		
		if not npc then
			coroutine.sleep(2)
			npc = find_box(p['Mob'])
		end
		
        if not npc then elseif (npc.name == box_name) then
            if p['Type'] == 'deru' then
				box_queue.push(p['Mob'])
			elseif p['Type'] == 'kesu' then
				if p['Mob'] == previous_chest then
					previous_chest = nil
					previous_chest_attempts = 0
				end
            end
        end
    end
end

local function start()
	if user_has_keys() then
		windower.add_to_chat(1,'Starting Aby Chests')                           
		open_chests = true
		coroutine.schedule(process_box_queue, 1)
	--	coroutine.schedule(process_item_queue, 5)
	else 
		windower.add_to_chat(1,'User has no keys, unable to start Aby Chests')                           
		open_chests = false
	end
end

local function stop()
	windower.add_to_chat(1,'Stopping Aby Chests')                           

	open_chests = false
end

local function toggle_debug()
	debug_mode = not debug_mode
	windower.add_to_chat(1,'Debug Mode: '..tostring(debug_mode)..'')                           
end

local function print_settings()
	local type_str = 'Type Settings: '
	
	for k,v in ipairs(settings.types) do
		type_str = type_str..'\n   %d:[%s]':format(k, v)
    end
	
	windower.add_to_chat(1,''..type_str..'')

	local red_lights_str = 'Red Light Settings: '
	
	 for k,v in ipairs(settings.red_lights) do
		red_lights_str = red_lights_str..'\n   %d:[%s]':format(k, v)
    end
	
	windower.add_to_chat(1,''..red_lights_str..'') 

	local gold_items_str = 'Gold Items Settings: '
	
	 for k,v in ipairs(settings.gold_items) do
		gold_items_str = gold_items_str..'\n   %d:[%s]':format(k, v)
    end
	
	windower.add_to_chat(1,''..gold_items_str..'')	
end

local function add_type(box_type) 
	box_type = box_type:lower()
	
	if has_value_table(box_types, box_type) then
		if settings.types:contains(box_type) then
			return 'Box type already selected to open'
		else 
			settings.types:append(box_type)
		end
	else 
		return 'Not a valid box type'
	end
end

local function add_light(light_type) 
	light_type = light_type:lower()
	
	if has_value_table(light_types, light_type) then
		if settings.red_lights:contains(light_type) then
			return 'Red light type already selected to open'
		else 
			settings.red_lights:append(light_type)
		end
	else 
		return 'Not a valid red light type'
	end
end

local function add_item(item) 
	item = item:lower()
	
	if settings.gold_items:contains(item) then
		return 'Gold item already selected to open'
	else 
		settings.gold_items:append(item)
	end
end

local function clear_types() 
	settings.types:clear()
end

local function clear_lights() 
	settings.red_lights:clear()
end

local function clear_items() 
	settings.gold_items:clear()
end

local function clear_all() 
	clear_items()
	clear_lights()
	clear_types()
end

local function handle_command(...)
    local cmd  = (...) and (...):lower()
    local args = {select(2, ...)}
    if commands[cmd] then
        local msg = commands[cmd](unpack(args))
        if msg then
            windower.add_to_chat(1,'Error running command: '..tostring(msg)..'')                           
        end
    else
		windower.add_to_chat(1,'Unknown command: '..cmd..'')                           
    end
end

commands['start'] = start
commands['stop'] = stop
commands['keys'] = user_has_keys
commands['debug'] = toggle_debug
commands['settings'] = print_settings
commands['save'] = save_file
commands['clear_types'] = clear_types
commands['clear_lights'] = clear_lights
commands['clear_items'] = clear_items
commands['clear_settings'] = clear_all
commands['add_type'] = add_type
commands['add_light'] = add_light
commands['add_item'] = add_item

windower.register_event('load',start)
windower.register_event('addon command', handle_command)
windower.register_event('incoming chunk', observe_box_spawn)
--windower.register_event('incoming chunk', examine_box)
windower.register_event('outgoing chunk', obtain_item)
