--! strict
local listener = {}

-- local variables
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

type InstanceStatus = "__inflight__" | "__dead__"

export type AttributeValue =
	string
| boolean
| number
| UDim
| UDim2
| BrickColor
| Color3
| Vector2
| Vector3
| CFrame
| NumberSequence
| ColorSequence
| NumberRange
| Rect
| Font

-- local public funcs
local function defaultGuard(_value: AttributeValue)
	return true
end

-- public funcs
function listener:observeAttribute(instance: Instance, name: string, callback: (value: AttributeValue) -> () -> (), guard: ((value: AttributeValue) -> boolean)?): () -> ()
	local cleanFn: (() -> ())? = nil

	local onAttrChangedConn: RBXScriptConnection
	local changedId = 0

	local valueGuard: (value: AttributeValue) -> boolean = if guard ~= nil then guard else defaultGuard

	local function OnAttributeChanged()
		if cleanFn ~= nil then
			task.spawn(cleanFn)
			cleanFn = nil
		end

		changedId += 1
		local id = changedId

		local value = instance:GetAttribute(name)

		if value ~= nil and valueGuard(value) then
			task.spawn(function()
				local clean = callback(value)
				if id == changedId and onAttrChangedConn.Connected then
					cleanFn = clean
				else
					task.spawn(clean)
				end
			end)
		end
	end

	-- Get changed values:
	onAttrChangedConn = instance:GetAttributeChangedSignal(name):Connect(OnAttributeChanged)

	-- Get initial value:
	task.defer(function()
		if not onAttrChangedConn.Connected then
			return
		end

		OnAttributeChanged()
	end)

	-- Cleanup:
	return function()
		onAttrChangedConn:Disconnect()
		if cleanFn ~= nil then
			task.spawn(cleanFn)
			cleanFn = nil
		end
	end
end

function listener:observeTag<T>(tag: string, callback: (instance: T) -> () -> (), ancestors: { Instance }?): () -> ()
	local instances: { [Instance]: InstanceStatus | () -> () } = {}
	local ancestryConn: { [Instance]: RBXScriptConnection } = {}

	local onInstAddedConn: RBXScriptConnection
	local onInstRemovedConn: RBXScriptConnection

	local function IsGoodAncestor(instance: Instance)
		if ancestors == nil then
			return true
		end

		for _, ancestor in ancestors do
			if instance:IsDescendantOf(ancestor) then
				return true
			end
		end

		return false
	end

	local function AttemptStartup(instance: Instance)
		-- Mark instance as starting up:
		instances[instance] = "__inflight__"

		-- Attempt to run the callback:
		task.defer(function()
			if instances[instance] ~= "__inflight__" then
				return
			end

			-- Run the callback in protected mode:
			local success, cleanup = xpcall(function(inst: T)
				local clean = callback(inst)
				assert(typeof(clean) == "function", "callback must return a function")
				return clean
			end, debug.traceback, instance :: any)

			-- If callback errored, print out the traceback:
			if not success then
				local err = ""
				local firstLine = string.split(cleanup :: any, "\n")[1]
				local lastColon = string.find(firstLine, ": ")
				if lastColon then
					err = firstLine:sub(lastColon + 1)
				end
				warn(`error while calling observeTag("{tag}") callback:{err}\n{cleanup}`)
				return
			end

			if instances[instance] ~= "__inflight__" then
				-- Instance lost its tag or was destroyed before callback completed; call cleanup immediately:
				task.spawn(cleanup :: any)
			else
				-- Good startup; mark the instance with the associated cleanup function:
				instances[instance] = cleanup :: any
			end
		end)
	end

	local function AttemptCleanup(instance: Instance)
		local cleanup = instances[instance]
		instances[instance] = "__dead__"

		if typeof(cleanup) == "function" then
			task.spawn(cleanup)
		end
	end

	local function OnAncestryChanged(instance: Instance)
		if IsGoodAncestor(instance) then
			if instances[instance] == "__dead__" then
				AttemptStartup(instance)
			end
		else
			AttemptCleanup(instance)
		end
	end

	local function OnInstanceAdded(instance: Instance)
		if not onInstAddedConn.Connected then
			return
		end
		if instances[instance] ~= nil then
			return
		end

		instances[instance] = "__dead__"

		ancestryConn[instance] = instance.AncestryChanged:Connect(function()
			OnAncestryChanged(instance)
		end)
		OnAncestryChanged(instance)
	end

	local function OnInstanceRemoved(instance: Instance)
		AttemptCleanup(instance)

		local ancestry = ancestryConn[instance]
		if ancestry then
			ancestry:Disconnect()
			ancestryConn[instance] = nil
		end

		instances[instance] = nil
	end

	-- Hook up added/removed listeners for the given tag:
	onInstAddedConn = CollectionService:GetInstanceAddedSignal(tag):Connect(OnInstanceAdded)
	onInstRemovedConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(OnInstanceRemoved)

	-- Attempt to mark already-existing tagged instances right away:
	task.defer(function()
		if not onInstAddedConn.Connected then
			return
		end

		for _, instance in CollectionService:GetTagged(tag) do
			task.spawn(OnInstanceAdded, instance)
		end
	end)

	-- Full observer cleanup function:
	return function()
		onInstAddedConn:Disconnect()
		onInstRemovedConn:Disconnect()

		-- Clear all instances:
		local instance = next(instances)
		while instance do
			OnInstanceRemoved(instance)
			instance = next(instances)
		end
	end
end

function listener:observePlayer(callback: (player: Player) -> (() -> ())?): () -> ()
	local playerAddedConn: RBXScriptConnection
	local playerRemovingConn: RBXScriptConnection

	local cleanupsPerPlayer: { [Player]: () -> () } = {}

	local function OnPlayerAdded(player: Player)
		if not playerAddedConn.Connected then
			return
		end

		task.spawn(function()
			local cleanup = callback(player)
			if typeof(cleanup) == "function" then
				if playerAddedConn.Connected and player.Parent then
					cleanupsPerPlayer[player] = cleanup
				else
					task.spawn(cleanup)
				end
			end
		end)
	end

	local function OnPlayerRemoving(player: Player)
		local cleanup = cleanupsPerPlayer[player]
		cleanupsPerPlayer[player] = nil
		if typeof(cleanup) == "function" then
			task.spawn(cleanup)
		end
	end

	-- Listen for changes:
	playerAddedConn = Players.PlayerAdded:Connect(OnPlayerAdded)
	playerRemovingConn = Players.PlayerRemoving:Connect(OnPlayerRemoving)

	-- Initial:
	task.defer(function()
		if not playerAddedConn.Connected then
			return
		end

		for _, player in Players:GetPlayers() do
			task.spawn(OnPlayerAdded, player)
		end
	end)

	-- Cleanup:
	return function()
		playerAddedConn:Disconnect()
		playerRemovingConn:Disconnect()

		local player = next(cleanupsPerPlayer)
		while player do
			OnPlayerRemoving(player)
			player = next(cleanupsPerPlayer)
		end
	end
end

function listener:observeCharacter(callback: (player: Player, character: Model) -> (() -> ())?): () -> ()
	return listener:observePlayer(function(player)
		local cleanupFn: (() -> ())? = nil

		local characterAddedConn: RBXScriptConnection

		local function OnCharacterAdded(character: Model)
			local currentCharCleanup: (() -> ())? = nil

			-- Call the callback:
			task.defer(function()
				local cleanup = callback(player, character)
				-- If a cleanup function is given, save it for later:
				if typeof(cleanup) == "function" then
					if characterAddedConn.Connected and character.Parent then
						currentCharCleanup = cleanup
						cleanupFn = cleanup
					else
						-- Character is already gone or observer has stopped; call cleanup immediately:
						task.spawn(cleanup)
					end
				end
			end)

			-- Watch for the character to be removed from the game hierarchy:
			local ancestryChangedConn: RBXScriptConnection
			ancestryChangedConn = character.AncestryChanged:Connect(function(_, newParent)
				if newParent == nil and ancestryChangedConn.Connected then
					ancestryChangedConn:Disconnect()
					if currentCharCleanup ~= nil then
						task.spawn(currentCharCleanup)
						if cleanupFn == currentCharCleanup then
							cleanupFn = nil
						end
						currentCharCleanup = nil
					end
				end
			end)
		end

		-- Handle character added:
		characterAddedConn = player.CharacterAdded:Connect(OnCharacterAdded)

		-- Handle initial character:
		task.defer(function()
			if player.Character and characterAddedConn.Connected then
				task.spawn(OnCharacterAdded, player.Character)
			end
		end)

		-- Cleanup:
		return function()
			characterAddedConn:Disconnect()
			if cleanupFn ~= nil then
				task.spawn(cleanupFn)
				cleanupFn = nil
			end
		end
	end)
end

function listener:observeProperty(instance: Instance, property: string, callback: (value: unknown) -> () -> ()): () -> ()
	local cleanFn: (() -> ())? = nil

	local propChangedConn: RBXScriptConnection
	local changedId = 0

	local function OnPropertyChanged()
		if cleanFn ~= nil then
			task.spawn(cleanFn)
			cleanFn = nil
		end

		changedId += 1
		local id = changedId

		local value = (instance :: any)[property]

		task.spawn(function()
			local clean = callback(value)
			if id == changedId and propChangedConn.Connected then
				cleanFn = clean
			else
				task.spawn(clean)
			end
		end)
	end

	-- Get changed values:
	propChangedConn = instance:GetPropertyChangedSignal(property):Connect(OnPropertyChanged)

	-- Get initial value:
	task.defer(function()
		if not propChangedConn.Connected then
			return
		end
		OnPropertyChanged()
	end)

	-- Cleanup:
	return function()
		propChangedConn:Disconnect()
		if cleanFn ~= nil then
			task.spawn(cleanFn)
			cleanFn = nil
		end
	end
end

return listener
