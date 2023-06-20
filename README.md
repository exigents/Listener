# Listener
An easier way to track property changes, attribute changes, tag changes, & players joining and leaving!

# Requiring the module
Require the module so you can use it.
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Listener = require(ReplicatedStorage:WaitForChild("Listener"))
```
# Player Listener
Detect players joining & leaving
```lua
Listener:observePlayer(function(player: Player)
    print(player.Name) --> Prints players name
    
    -- Return a function to call once the player leaves or the listener is stopped
    return function()
        print(player.Name.." Left or listener stopped.") --> Prints players name "Left or listener stopped"
    end
end)
```

# Attribute Listener
Detect when an attribute is changed.
```lua
local Part = workspace.Part
local AttributeName = "Health"

Listener:observeAttribute(Part, AttributeName, function(value)
    print("Attribute is", value) --> prints the value of the attribute
    
    -- return a function to call when the attribute is changed again to a value different than value
    return function()
        print("Attribute is no longer", value) --> prints that the attribute is no longer a value
    end
end)
```

# Character Listener
Detect when a character is added
```lua
Listener:observeCharacter(function(player: Player, character: Model)
	print(player.Name) --> prints players name
	print(character:FindFirstChild("Humanoid").Health) --> 100
	
	local humanoid = character:FindFirstChild("Humanoid")
	
	-- Listen to humanoid Died event:
	local onDiedConn: RBXScriptConnection? = nil
	if humanoid then
		onDiedConn = humanoid.Died:Connect(function()
			print("Character died for " .. player.Name)
		end)
	end
	
	return function()
		print("Character Removed") --> Character Removed
		if onDiedConn ~= nil then
			onDiedConn:Disconnect()
			onDiedConn = nil
		end
	end
end)
```

# Properties Listener
Detect when a property is changed on a object
```lua
local Part = workspace.Part
local PropertyName = "Size"

Listener:observeProperty(Part, PropertyName, function(value)
    print("New Size.X: "..tostring(value.X)) --> prints the X value of the size
    
    return function()
        print("The Size.X Is no longer: "..tostring(value.X)) --> prints the size.x is no longer: X
    end
end)
```
