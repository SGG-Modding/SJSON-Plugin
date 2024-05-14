---@meta _
---@diagnostic disable

---@module 'SGG_Modding-ENVY'
local envy = rom.mods['SGG_Modding-ENVY']
---@module 'SGG_Modding-ENVY-auto'
envy.auto()

private.sjson = import "hsjson.lua"

local folder_content = rom.paths.Content()
local folder_game = rom.path.combine(folder_content,'Game')

local function get_content_data_path(relative_path)
	if relative_path == nil then
		return folder_content
	end
	return rom.path.combine(folder_content,relative_path)
end

local function get_game_data_path(relative_path)
	if relative_path == nil then
		return folder_game
	end
	return rom.path.combine(folder_game,relative_path)
end

local load_callbacks = {}

local function handle_sjson_data(path,data)
	local callbacks = load_callbacks[path]
	if not callbacks then return data end
	for _,callback in ipairs(callbacks) do
		local newdata = callback(data)
		if newdata ~= nil then
			data = newdata
		end
	end
	return data
end

local function handle_sjson_content(path,content)
	local data, _, msg = sjson.decode(content)
	if msg then error(msg) end
	data = handle_sjson_data(path,data)
	return sjson.encode(data)
end

local function prepare_callbacks(path)
	local callbacks = load_callbacks[path]
	if callbacks then return callbacks end
	rom.data.on_sjson_read_as_string(function(_,content)
		return handle_sjson_content(path,content)
	end, path)
	callbacks = {}
	load_callbacks[path] = callbacks
	return callbacks
end

public.get_content_data_path = get_content_data_path
public.get_game_data_path = get_game_data_path

public.decode = sjson.decode
public.encode = sjson.encode

function public.decode_file(path)
	local file, msg = io.open(path)
	if file == nil then error(msg) end
	local content = file:read('*all')
	file:close()
	return sjson.decode(content)
end

function public.encode_file(path,data,state)
	local content = sjson.encode(data,state)
	rom.path.create_directory(rom.path.get_parent(path))
	local file, msg = io.open(path,'w')
	if file == nil then error(msg) end
	file:write(content)
	file:close()
end

public.null = sjson.null

public.is_array = sjson.is_array

function public.to_array(data)
	data = data or {}
	local meta = getmetatable(data) or {}
	meta.__sjsontype = 'array'
	return setmetatable(data,meta)
end

function public.to_object(data,order)
	data = data or {}
	local meta = getmetatable(data) or {}
	meta.__sjsontype = 'object'
	if order then meta.__sjsonorder = order end
	return setmetatable(data,meta)
end

function public.get_order(data)
	local meta = getmetatable(data)
	if not meta then return nil end
	return meta.__sjsontype
end

function public.join_order(orderA, orderB)
	local order = {}
	local values = {}
	local n = 0
	
	for i,v in ipairs(orderA) do
		order[i] = v
		values[v] = true
		n = i
	end
	
	for _,v in ipairs(orderB) do
		if not values[v] then
			n = n + 1
			order[n] = v
		end
	end
	
	return order
end

public.hook = function(path,callback)	
	local callbacks = prepare_callbacks(path)
	table.insert(callbacks,callback)
end