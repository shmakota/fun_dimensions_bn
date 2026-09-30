local mod = game.mod_runtime[game.current_mod]

---@param params { user: Character, pos: TripointBubMs }
game.examine_functions["DIMENSION_MAINTENANCE"] = function(params) mod.examine_maintenance(params) end

---@param params { user: Character, pos: TripointBubMs }
game.examine_functions["DIMENSION_LIMBO_RIFT"] = function(params) mod.enter_limbo_rift(params) end

---@param params { user: Character, pos: TripointBubMs }
game.examine_functions["DIMENSION_WATERWORLD_ENTER"] = function(params) mod.enter_waterworld_portal(params) end

---@param params { user: Character, pos: TripointBubMs }
game.examine_functions["DIMENSION_WATERWORLD_PORTAL_RETURN"] = function(params) mod.return_from_waterworld_portal(params) end

---@param params { user: Character, item: Item, pos: TripointBubMs }
