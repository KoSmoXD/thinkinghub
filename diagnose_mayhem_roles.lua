-- Read-only diagnostic. No movement, remotes, hooks or role overrides.
local Players=game:GetService("Players")
local player=assert(Players.LocalPlayer,"Run this on the client")
local gui=Instance.new("ScreenGui")
gui.Name="MayhemRoleReport"
gui.ResetOnSpawn=false
gui.DisplayOrder=10000
local parent=player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui",10)
assert(parent,"PlayerGui unavailable")
local previous=parent:FindFirstChild(gui.Name)
if previous then previous:Destroy() end
gui.Parent=parent
local frame=Instance.new("Frame")
frame.Size=UDim2.new(.85,0,.75,0)
frame.Position=UDim2.new(.075,0,.12,0)
frame.BackgroundColor3=Color3.fromRGB(25,25,30)
frame.Parent=gui
local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-90,0,40)
title.BackgroundTransparency=1
title.TextColor3=Color3.new(1,1,1)
title.Text="ROLE REPORT — Right Shift to close"
title.TextSize=15
title.Parent=frame
local close=Instance.new("TextButton")
close.Size=UDim2.new(0,80,0,34)
close.Position=UDim2.new(1,-85,0,3)
close.Text="Close"
close.Modal=true -- Release first-person mouse lock while the button is visible.
close.Parent=frame
close.Activated:Connect(function()gui:Destroy()end)
local inputConnection=game:GetService("UserInputService").InputBegan:Connect(function(input)
    if input.KeyCode==Enum.KeyCode.RightShift then gui:Destroy() end
end)
gui.Destroying:Connect(function()inputConnection:Disconnect()end)
local scroll=Instance.new("ScrollingFrame")
scroll.Position=UDim2.new(0,8,0,45)
scroll.Size=UDim2.new(1,-16,1,-53)
scroll.BackgroundTransparency=1
scroll.ScrollBarThickness=8
scroll.Parent=frame
local box=Instance.new("TextBox")
box.Size=UDim2.new(1,-15,0,100)
box.BackgroundTransparency=1
box.TextColor3=Color3.new(1,1,1)
box.TextSize=14
box.Font=Enum.Font.Code
box.TextXAlignment=Enum.TextXAlignment.Left
box.TextYAlignment=Enum.TextYAlignment.Top
box.ClearTextOnFocus=false
box.MultiLine=true
box.TextWrapped=true
box.Text="Collecting role information..."
box.Parent=scroll
local rows={"PlaceId="..tostring(game.PlaceId).." GameId="..tostring(game.GameId)}
local function add(s) if #rows<240 then rows[#rows+1]=s end end
local function relevant(name)
    name=tostring(name):lower()
    for _,term in ipairs({"role","team","entity","monster","surviv","character","faction","class","morph","halt"}) do
        if name:find(term,1,true) then return true end
    end
    return false
end
local function describe(obj,path,depth)
    add(path.." ["..obj.ClassName.."]")
    for key,value in pairs(obj:GetAttributes()) do
        if relevant(key) then add(path.." @"..key.."="..tostring(value):sub(1,160)) end
    end
    local count=0
    for _,child in ipairs(obj:GetChildren()) do
        count=count+1
        if count>60 or #rows>=240 then break end
        local childPath=path.."/"..child.Name
        if relevant(child.Name) then
            if child:IsA("StringValue") or child:IsA("BoolValue") or child:IsA("IntValue") then
                add(childPath.."="..tostring(child.Value):sub(1,160))
            else add(childPath.." ["..child.ClassName.."]") end
        end
        -- Inspect bounded metadata containers, never inventory or UI trees.
        if depth<2 and (child:IsA("Folder") or child:IsA("Configuration")
            or child:IsA("Humanoid")) then describe(child,childPath,depth+1) end
    end
end
local ok,err=pcall(function()
    add("LOCAL team="..tostring(player.Team and player.Team.Name).." neutral="..tostring(player.Neutral))
    describe(player,"LOCAL Player",0)
    if player.Character then describe(player.Character,"LOCAL Character:"..player.Character.Name,0) end
    if player.Team then describe(player.Team,"LOCAL Team",0) end
    for i,other in ipairs(Players:GetPlayers()) do
        if i>12 then break end
        if other~=player then
            add("OTHER "..i.." team="..tostring(other.Team and other.Team.Name).." neutral="..tostring(other.Neutral))
            describe(other,"OTHER "..i.." Player",0)
            if other.Character then describe(other.Character,"OTHER "..i.." Character",0) end
        end
    end
end)
if not ok then add("Diagnostic error: "..tostring(err)) end
local report=table.concat(rows,"\n")
box.Text=report
box.Size=UDim2.new(1,-15,0,math.max(100,#rows*34))
scroll.CanvasSize=UDim2.new(0,0,0,math.max(100,#rows*34))
print("[MAYHEM ROLE REPORT]\n"..report)
return report
