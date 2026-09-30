local mod = game.mod_runtime[game.current_mod]
local mod_id = game.current_mod

---@class MaintenanceEndpoint
---@field world string
---@field x integer
---@field y integer
---@field z integer

---@param world string
---@param pos TripointAbsMs
local function endpoint(world, pos) return { world = world, x = pos.x, y = pos.y, z = pos.z } end

---@param point MaintenanceEndpoint
local function key(point) return string.format("%s:%d:%d:%d", point.world, point.x, point.y, point.z) end

---@param point MaintenanceEndpoint
local function absolute(point) return TripointAbsMs.new(point.x, point.y, point.z) end

---@param world string
local function manhole_id(world)
  return FurnId.new(world == "megacity" and "f_maintenance_to_default" or "f_maintenance_to_megacity"):int_id()
end

---@param world string
local function cross_dimension(world)
  -- A single-action item delegates dimension switching to the existing travel actor.
  local passage = gapi.create_item(ItypeId.new("dimension_maintenance_" .. world), 1)
  passage:invoke_at(gapi.get_avatar():bub_pos())
end

---@param params { user: Character, pos: TripointBubMs }
mod.enter_limbo_rift = function(params)
  if not params.user:is_avatar() then return end

  local source_world = gapi.get_map():get_ter_at(params.pos) == TerId.new("t_limbo"):int_id()
    and "test_dimension"
    or "default"
  local target_world = source_world == "default" and "test_dimension" or "default"
  local source = endpoint(source_world, gapi.bub_to_abs(params.pos))
  local storage = game.mod_storage[mod_id]
  storage.limbo_rift_links = storage.limbo_rift_links or {}
  local links = storage.limbo_rift_links
  local destination = links[key(source)]
  cross_dimension(target_world)

  if destination then
    local target = absolute(destination)
    gapi.place_player_overmap_at(target:to_omt())
    gapi.place_player_local_at(gapi.abs_to_bub(target))
  end
  local arrival = gapi.get_avatar():abs_pos()
  local opposite = endpoint(target_world, arrival)
  links[key(source)] = opposite
  links[key(opposite)] = source
  gapi.get_map():set_furn_at(gapi.get_avatar():bub_pos(), FurnId.new("f_limbo_rift"):int_id())
  gapi.add_msg(locale.gettext("The rift opens into the other dimension, where a matching portal stabilizes."))
end

---@param point MaintenanceEndpoint
local function relocate(point)
  local pos = absolute(point)
  gapi.place_player_overmap_at(pos:to_omt())
  gapi.place_player_local_at(gapi.abs_to_bub(pos))
end

---@param world string
---@param origin TripointAbsOmt
---@param links table<string, MaintenanceEndpoint>
local function find_exit(world, origin, links)
  local search = OmtFindParams.new()
  search:add_type("urban_subway", OtMatchType.PREFIX)
  search:set_search_range(0, 180)
  search:set_search_layers(-4, -1)
  search.max_results = 64
  search.existing_only = false

  local no_trap = TrapId.new("tr_null"):int_id()
  local floor = TerId.new("t_floor"):int_id()
  local expected_furniture = manhole_id(world)

  for _, omt in ipairs(overmapbuffer.find_all(origin, search)) do
    gapi.place_player_overmap_at(omt)
    local map = gapi.get_map()
    for y = 0, 23 do
      for x = 0, 23 do
        local point = endpoint(world, TripointAbsMs.new(omt.x * 24 + x, omt.y * 24 + y, omt.z))
        local pos = gapi.abs_to_bub(absolute(point))
        if links[key(point)] == nil and map:get_furn_at(pos) == expected_furniture and
          map:get_trap_at(pos) == no_trap and map:get_ter_at(pos) == floor then
          local occupant = gapi.get_creature_at(pos)
          if occupant == nil or occupant:is_avatar() then return point end
        end
      end
    end
  end
  return nil
end

---@param point MaintenanceEndpoint
local function has_exit(point)
  local pos = gapi.abs_to_bub(absolute(point))
  local map = gapi.get_map()
  return overmapbuffer.check_ot("urban_subway", OtMatchType.PREFIX, absolute(point):to_omt()) and
         map:get_furn_at(pos) == manhole_id(point.world) and
         map:get_ter_at(pos) == TerId.new("t_floor"):int_id()
end

---@param params { user: Character, pos: TripointBubMs }
mod.examine_maintenance = function(params)
  if not params.user:is_avatar() then return end
  local furniture = gapi.get_map():get_furn_at(params.pos)
  local source_world
  if furniture == manhole_id("default") then
    source_world = "default"
  elseif furniture == manhole_id("megacity") then
    source_world = "megacity"
  else
    gapi.add_msg(locale.gettext("The cover will not budge."))
    return
  end

  local prompt = QueryPopup.new()
  prompt:message(locale.gettext("Lift the maintenance cover and descend the ladder?"))
  if prompt:query_yn() ~= "YES" then return end

  local source = endpoint(source_world, gapi.bub_to_abs(params.pos))
  local start = endpoint(source_world, params.user:abs_pos())
  local target_world = source_world == "default" and "megacity" or "default"
  -- Read storage at use time: loading a save can replace its table.
  local storage = game.mod_storage[mod_id]
  storage.maintenance_links = storage.maintenance_links or {}
  local links = storage.maintenance_links
  local destination = links[key(source)]

  local ok = pcall(function()
    cross_dimension(target_world)
    if destination then
      relocate(destination)
      if not has_exit(destination) then
        links[key(destination)] = nil
        destination = nil
      end
    end
    if destination == nil then
      destination = find_exit(target_world, params.user:abs_pos():to_omt(), links)
      if destination == nil then return false end
      relocate(destination)
    end
  end)

  if not ok or destination == nil then
    cross_dimension(source_world)
    relocate(start)
    gapi.add_msg(locale.gettext("The passage doubles back.  You climb out where you started."))
    return
  end

  links[key(source)] = destination
  links[key(destination)] = source
  gapi.add_msg(locale.gettext("You emerge into a maintenance room.  The station beyond sounds different."))
end

---@param params { user: Character, pos: TripointBubMs }
mod.enter_waterworld_portal = function(params)
  if not params.user:is_avatar() then return end
  local home = gapi.bub_to_abs(params.pos)
  local storage = game.mod_storage[mod_id]
  storage.waterworld_portal_home = { x = home.x, y = home.y, z = home.z }
  cross_dimension("waterworld_islands")
  local origin = params.user:abs_pos()
  local search_origin = TripointAbsOmt.new(math.floor(origin.x / 24), math.floor(origin.y / 24), 0)
  local search = OmtFindParams.new()
  search:add_type("dimension_waterworld_portal_bed", OtMatchType.TYPE)
  search:set_search_range(0, 180)
  search:set_search_layers(-5, -5)
  search.max_results = 24
  search.existing_only = false
  for _, omt in ipairs(overmapbuffer.find_all(search_origin, search)) do
    gapi.place_player_overmap_at(omt)
    local target = TripointAbsMs.new(omt.x * 24 + 12, omt.y * 24 + 12, omt.z)
    local pos = gapi.abs_to_bub(target)
    if gapi.get_map():get_furn_at(pos) == FurnId.new("f_waterworld_portal_return"):int_id() then
      gapi.place_player_local_at(pos)
      gapi.add_msg(locale.gettext("You pass through the portal and emerge on the lake bed in another world."))
      return
    end
  end
  cross_dimension("default")
  gapi.place_player_overmap_at(home:to_omt())
  gapi.place_player_local_at(gapi.abs_to_bub(home))
  gapi.add_msg(locale.gettext("The portal has no stable counterpart and returns you to its lake bed."))
end

---@param params { user: Character, pos: TripointBubMs }
mod.return_from_waterworld_portal = function(params)
  if not params.user:is_avatar() then return end
  local storage = game.mod_storage[mod_id]
  local home = storage.waterworld_portal_home
  cross_dimension("default")
  if home then
    local target = TripointAbsMs.new(home.x, home.y, home.z)
    gapi.place_player_overmap_at(target:to_omt())
    gapi.place_player_local_at(gapi.abs_to_bub(target))
    gapi.add_msg(locale.gettext("You emerge beside the underwater portal you entered."))
    return
  end

  local origin = params.user:abs_pos()
  local search_origin = TripointAbsOmt.new(math.floor(origin.x / 24), math.floor(origin.y / 24), 0)
  local search = OmtFindParams.new()
  search:add_type("dimension_waterworld_portal_bed", OtMatchType.TYPE)
  search:set_search_range(0, 180)
  search:set_search_layers(-5, -5)
  search.max_results = 24
  search.existing_only = false
  for _, omt in ipairs(overmapbuffer.find_all(search_origin, search)) do
    gapi.place_player_overmap_at(omt)
    local target = TripointAbsMs.new(omt.x * 24 + 12, omt.y * 24 + 12, omt.z)
    local pos = gapi.abs_to_bub(target)
    if gapi.get_map():get_furn_at(pos) == FurnId.new("f_waterworld_portal_enter"):int_id() then
      gapi.place_player_local_at(pos)
      gapi.add_msg(locale.gettext("You emerge beside an underwater portal on the lake bed."))
      return
    end
  end
  gapi.add_msg(locale.gettext("The portal has no stable counterpart in this world."))
end
