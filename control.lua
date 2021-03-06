require "util"

local INVENTORY_COLUMNS = 10

-- Name of the row headers we put in the UI
local filterUiElementName = "FilterFillRow"
local requestUiElementName = "RequestRow"

-- Button click dispatching
local Buttons = {}
local dispatch = {}

function debug_print(msg)
    for _, player in pairs(game.players) do
        player.print("[fast-filter-fill] " .. serpent.block(msg))
    end
end

function table_length(tbl)
   local cnt = 0
   for _, _ in pairs(tbl) do
       cnt = cnt + 1
   end
   return cnt
end

-- Initializes the world
function startup()
    script.on_event(defines.events.on_gui_opened, checkOpened)
    script.on_event(defines.events.on_gui_closed, checkOpened)
    initButtons()
end

-- Listener for events clicked
function handleButton(event)
    local handler = dispatch[event.element.name]
    if handler then
        handler(game.players[event.player_index])
    end
end

-- Initializes event handlers and button names
function initButtons()
    function register(category, name, func)
        local buttonName = category .. '_' .. name
        Buttons[category][name] = buttonName
        dispatch[buttonName] = func
    end
    -- Filtering
    Buttons.Filter = {}
    register('Filter', 'All', filter_fillAll)
    register('Filter', 'Right', filter_fillRight)
    register('Filter', 'Down', filter_fillDown)
    register('Filter', 'Clear', filter_clearAll)
    register('Filter', 'Set', filter_setAll)
    -- Logistic Requests
    Buttons.Requests = {}
    register('Requests', 'x2', requests_x2)
    register('Requests', 'x5', requests_x5)
    register('Requests', 'x10', requests_x10)
    register('Requests', 'Fill', requests_fill)
    register('Requests', 'Blueprint', requests_blueprint)

    script.on_event(defines.events.on_gui_click, handleButton)
end

function canFilter(player)
	if player.opened_gui_type ~= defines.gui_type.entity then
		return false
	end

	inv = player.opened.get_output_inventory()
    return inv ~= nil and inv.supports_filters()
end

function canRequest(obj)
    return obj.request_slot_count ~= nil and obj.request_slot_count > 0
end

-- See if an applicable container is opened and show/hide the UI accordingly.
-- Some delay is imperceptible here, so only check this once every few ticks
-- to avoid performance impact
function checkOpened(evt)
    local player = game.players[evt.player_index]

    showOrHideFilterUI(player, canFilter(player))
    showOrHideRequestUI(player, canFilter(player))
end

-- Gets the name of the item at the given position, or nil if there
-- is no item at that position
function getItemAtPosition(player, n)
    local inv = player.opened.get_output_inventory()
    local isEmpty = not inv[n].valid_for_read
    if isEmpty then
        return nil
    else
        return inv[n].name
    end
end

-- Returns either the item at a position, or the filter
-- at the position if there isn't an item there
function getItemOrFilterAtPosition(player, n)
    local filter = player.opened.get_output_inventory().get_filter(n)
    if filter ~= nil then
        return filter
    else
        return getItemAtPosition(player, n)
    end
end

-- Filtering: Clear all filters in the opened container
function filter_clearAll(player)
    local op = player.opened.get_output_inventory();
    local size = #op
    for i = 1, size do
        op.set_filter(i, nil)
    end
end

-- Filtering: Set the filters of the opened container to the
-- contents of each cell
function filter_setAll(player)
    local op = player.opened.get_output_inventory();
    local size = #op
    for i = 1, size do
        local desired = getItemAtPosition(player, i)
        op.set_filter(i, desired)
    end
end

-- Filtering: Filter all cells of the opened container with the
-- contents of the player's cursor stack, or the first item in the container,
-- or the first filter in the container
function filter_fillAll(player)
    -- Get the contents of the player's cursor stack, or the first cell
    local desired = (player.cursor_stack.valid_for_read and player.cursor_stack.name) or getItemOrFilterAtPosition(player, 1)
    local op = player.opened.get_output_inventory();
    local size = #op
    for i = 1, size do
        local current = getItemAtPosition(player, i)
        if current and desired and current ~= desired then
            player.print({"", 'Skipped setting a filter on the cell occupied by ', {'item-name.' .. current}})
        else
            op.set_filter(i, desired or nil)
        end
    end
end

-- Filtering: Copies the filter settings of each cell to the cell(s) to the right of it
function filter_fillRight(player)
    local op = player.opened.get_output_inventory()
    local size = #op

    local rows = math.ceil(size / INVENTORY_COLUMNS)
    for r = 1, rows do
        local desired = getItemOrFilterAtPosition(player, 1 + (r - 1) * INVENTORY_COLUMNS)
        for c = 1, INVENTORY_COLUMNS do
            local i = c + (r - 1) * INVENTORY_COLUMNS
            if i <= size then
                desired = getItemAtPosition(player, i) or desired
                op.set_filter(i, desired)
            end
        end
    end
end

-- Filtering: Copies the filter settings of each cell to the cell(s) below it
function filter_fillDown(player)
    local op = player.opened.get_output_inventory()
    local size = #op

    local rows = math.ceil(size / INVENTORY_COLUMNS)
    for c = 1, INVENTORY_COLUMNS do
        local desired = getItemOrFilterAtPosition(player, c)
        for r = 1, rows do
            local i = c + (r - 1) * INVENTORY_COLUMNS
            if i <= size then
                desired = getItemAtPosition(player, i) or desired
                op.set_filter(c + (r - 1) * INVENTORY_COLUMNS, desired)
            end
        end
    end
end

function multiply_filter(player, factor)
    for i = 1, player.opened.request_slot_count do
        local existing = player.opened.get_request_slot(i)
        if existing ~= nil then
            player.opened.set_request_slot({ name =  existing.name, count = math.floor(existing.count * factor) }, i)
        end
    end
end

function requests_x2(player)
    multiply_filter(player, 2)
end
function requests_x5(player)
    multiply_filter(player, 5)
end
function requests_x10(player)
    multiply_filter(player, 10)
end
function requests_fill(player)
    local inv = player.opened.get_output_inventory()
    local inventorySize = #inv

    local totalStackRequests = 0

    -- Add up how many total stacks we need here
    for i = 1, player.opened.request_slot_count do
        local item = player.opened.get_request_slot(i)
        if item ~= nil then
            totalStackRequests = totalStackRequests + item.count / game.item_prototypes[item.name].stack_size
        end
    end

    local factor = inventorySize / totalStackRequests
    -- Go back and re-set each thing according to its rounded-up stack size
    for i = 1, player.opened.request_slot_count do
        local item = player.opened.get_request_slot(i)
        if item ~= nil then
            stacksToRequest = math.ceil(item.count / game.item_prototypes[item.name].stack_size)
            numberToRequest = stacksToRequest * game.item_prototypes[item.name].stack_size
            player.opened.set_request_slot({ name =  item.name, count = numberToRequest }, i)
        end
    end
end

function requests_blueprint(player)
    -- Get some blueprint details
    local blueprint = nil;
    if player.cursor_stack.is_blueprint then
        blueprint = player.cursor_stack;
    elseif player.opened.get_output_inventory()[1].is_blueprint then
        blueprint = player.opened.get_output_inventory()[1];
    else
        player.print('You must be holding a blueprint or have a blueprint in the first chest slot to use this button')
        return
    end

    -- Clear out all existing requests
    for i = 1, player.opened.request_slot_count do
        player.opened.clear_request_slot(i)
    end

    if not blueprint.is_blueprint_setup() then
        player.print('Blueprint has no pattern. Please use blueprint with pattern.')
        return
    end

    if table_length(blueprint.cost_to_build) > player.opened.request_slot_count then
        player.print('Blueprint has more entities than would fit in the request slots of this chest')
        return
    end

    -- Set the requests in the chest
    local i = 1
    for k, v in pairs(blueprint.cost_to_build) do
        player.opened.set_request_slot({name = k, count = v}, i)
        i = i + 1
    end
end


-- UI management
function showOrHideUI(player, show, name, showFunc)
    local exists = player.gui.top[name] ~= nil;
    if exists ~= show then
        if show then
            player.gui.top.add({ type = "flow", name = name, direction = "horizontal" });
            showFunc(player.gui.top[name])
        else
            player.gui.top[name].destroy()
        end
    end
end

function showOrHideFilterUI(player, show)
    showOrHideUI(player, show, 'FilterRowName', showFilterUI)
end

function showFilterUI(myRow)
    myRow.add( { type = "button", caption = "Filters: " } )

    myRow.add( { type = "button", name = Buttons.Filter.All, caption = "Fill All" } )
    myRow.add( { type = "button", name = Buttons.Filter.Right, caption = "Fill Right" } )
    myRow.add( { type = "button", name = Buttons.Filter.Down, caption = "Fill Down" } )
    myRow.add( { type = "button", name = Buttons.Filter.Clear, caption = "Clear All" } )
    myRow.add( { type = "button", name = Buttons.Filter.Set, caption = "Set All" } )
end

function showOrHideRequestUI(player, show)
    showOrHideUI(player, show, 'RequestRowName', showRequestUI)
end

function showRequestUI(myRow)
    myRow.add( { type = "button", caption = "Requests: " } )

    myRow.add( { type = "button", name = Buttons.Requests.x2, caption = "x2" } )
    myRow.add( { type = "button", name = Buttons.Requests.x5, caption = "x5" } )
    myRow.add( { type = "button", name = Buttons.Requests.x10, caption = "x10" } )
    myRow.add( { type = "button", name = Buttons.Requests.Fill, caption = "Fill" } )
    myRow.add( { type = "button", name = Buttons.Requests.Blueprint, caption = "Blueprint" } )
end

script.on_init(startup)
script.on_load(startup)
