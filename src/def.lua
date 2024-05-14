---@meta SGG_Modding-SJSON
local sjson = {}

---@class SGG_Modding-SJSON*null
---@alias SGG_Modding-SJSON*value boolean|number|SGG_Modding-SJSON*null|SGG_Modding-SJSON*array|SGG_Modding-SJSON*object
---@alias SGG_Modding-SJSON*array SGG_Modding-SJSON*value[]
---@alias SGG_Modding-SJSON*object table<string,SGG_Modding-SJSON*value>

---@param path string relative path from the game's Content folder
---@return string path absolute path
function sjson.get_content_data_path(path) end

---@param path string relative path from the game's Game folder
---@return string path absolute path
function sjson.get_game_data_path(path) end

---@param content string
---@return SGG_Modding-SJSON*object data
function sjson.decode(content) end

---@param data SGG_Modding-SJSON*object
---@param state table?
---@return string content
function sjson.encode(data,state) end

---@param path string
function sjson.decode_file(path) end

---@param path string
---@param data SGG_Modding-SJSON*object
---@param state table?
function sjson.encode_file(path,data,state) end

---@type SGG_Modding-SJSON*null
sjson.null = {}

---@param data table
---@return boolean is_array
function sjson.is_array(data) end


---@param data table
---@return SGG_Modding-SJSON*array array
function sjson.to_array(data) end

---@param data table
---@param order string[]
---@return SGG_Modding-SJSON*object object
function sjson.to_object(data,order) end

---@param data SGG_Modding-SJSON*object
---@return string[] order
function sjson.get_order(data) end

---@param orderA string[]
---@param orderB string[]
---@return string[] order
function sjson.join_order(orderA, orderB) end

---@param path string
---@param patch fun(data: SGG_Modding-SJSON*object): data: SGG_Modding-SJSON*object?
function sjson.hook(path,patch) end

return sjson