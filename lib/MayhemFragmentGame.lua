-- Zinc Hub | DOORS MAYHEM glitch fragment objective assistant (beta)
-- Handles nearby fragment prompts and GUIs with EXPLICIT correct answers.
-- Unknown puzzle mechanisms are diagnosed, never brute-forced.
local Module = {}
local function norm(v)
    return tostring(v or ""):lower():gsub("[^%w]","")
end
local function attr(item,key)
    if not item then return nil end
    local ok,value=pcall(item.GetAttribute,item,key)
    return ok and value or nil
end
local function children(item)
    if not item then return {} end
    local ok,out=pcall(item.GetDescendants,item)
    return ok and type(out)=="table" and out or {}
end
local function isa(item,what)
    if not item then return false end
    local ok,result=pcall(item.IsA,item,what)
    return ok and result == true
end
local function visible(item)
    local node=item
    while node do
        if isa(node,"GuiObject") and node.Visible==false then return false end
        if isa(node,"ScreenGui") and node.Enabled==false then return false end
        node=node.Parent
    end
    return true
end
local function buttonText(item)
    local ok,value=pcall(function() return item.Text end)
    return ok and type(value)=="string" and value or ""
end
local function puzzleName(name, extra)
    local value=norm(name)
    return value=="glitchfragment" or value=="glitchpuzzle"
        or value=="fragmentpuzzle" or value=="fragmentgame"
        or value=="glitchfragmentminigame" or value=="glitchfragmentgame"
        or value=="fragmentminigame" or (extra~="" and value==extra)
end
local function matchText(expected,button)
    local want=norm(expected)
    if want=="" then return false end
    return want==norm(buttonText(button)) or want==norm(button.Name)
        or want==norm(attr(button,"Value")) or want==norm(attr(button,"Answer"))
end
local function getExpected(root,button)
    local node=button.Parent
    while node do
        for _,key in ipairs({"CorrectAnswer","ExpectedAnswer",
            "Solution","TargetValue","NextAnswer"}) do
            local value=attr(node,key)
            if (type(value)=="string" or type(value)=="number")
                and tostring(value)~="" then return value end
        end
        if node==root then break end
        node=node.Parent
    end
end
function Module.new(deps)
    assert(type(deps)=="table" and deps.player
        and type(deps.isFragment)=="function","fragment objective dependencies required")
    local self={
        enabled=false,player=deps.player,isFragment=deps.isFragment,
        activatePrompt=deps.activatePrompt,clickButton=deps.clickButton,
        guiAlias="",now=0,scanAt=0,lastClick=-math.huge,
        lastPrompt=-math.huge,attempted=setmetatable({},{__mode="k"}),
        clicks=0,prompts=0,puzzles=0,unsupported=0,
        status="Off",lastPuzzle=nil,clickedSteps={},diagnostics={},
    }
    local function playerRoot()
        local c=self.player.Character
        if not c then return nil end
        return c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart
    end
    local function promptAvailable(prompt)
        if not prompt or not isa(prompt,"ProximityPrompt")
            or prompt.Enabled==false then return false end
        if self.attempted[prompt] then return false end
        local root=playerRoot()
        if not root then return false end
        local part=prompt.Parent
        while part and not isa(part,"BasePart") do
            if part==deps.workspace then return false end
            part=part.Parent
        end
        if not part or not part.Position then return false end
        local max=math.min(15,math.max(3,tonumber(prompt.MaxActivationDistance) or 10))
        local distance=(root.Position-part.Position).Magnitude
        return distance <= max
    end
    local function candidates()
        local result={}
        local world=deps.workspace
        for _,instance in ipairs(children(world)) do
            if isa(instance,"ProximityPrompt") and self.isFragment(instance) then
                local safe=true
                if deps.inCharacter then safe=not deps.inCharacter(instance) end
                if safe and promptAvailable(instance) then
                    result[#result+1]=instance
                end
            end
        end
        return result
    end
    local function guiRoots()
        local pg=self.player:FindFirstChild("PlayerGui")
        if not pg then return {} end
        local roots={}
        for _,item in ipairs(children(pg)) do
            if (isa(item,"ScreenGui") or isa(item,"Frame"))
                and puzzleName(item.Name,norm(self.guiAlias))
                and visible(item) then
                roots[#roots+1]=item
            end
        end
        return roots
    end
    local function puzzleButtons(root)
        local buttons={}
        for _,item in ipairs(children(root)) do
            if isa(item,"GuiButton") and visible(item) then
                buttons[#buttons+1]=item
            end
        end
        return buttons
    end
    local function answerFor(root)
        local buttons=puzzleButtons(root)
        local explicit={}
        for _,button in ipairs(buttons) do
            if attr(button,"IsCorrect")==true
                or attr(button,"Correct")==true
                or attr(button,"IsAnswer")==true then
                explicit[#explicit+1]=button
            end
        end
        if #explicit==1 then return explicit[1],#buttons end
        if #explicit>1 then return nil,#buttons end
        local found={}
        for _,button in ipairs(buttons) do
            local expected=getExpected(root,button)
            if expected~=nil and matchText(expected,button) then
                found[#found+1]=button
            end
        end
        if #found==1 then return found[1],#buttons end
        return nil,#buttons
    end
    function self:SetEnabled(value)
        self.enabled=value==true
        self.status=self.enabled and "Waiting for Hotel fragment puzzle" or "Off"
        self.scanAt=0;self.lastClick=-math.huge
        self.lastPrompt=-math.huge
        self.lastPuzzle=nil
        self.clickedSteps={}
        self.attempted=setmetatable({},{__mode="k"})
    end
    function self:Step(dt)
        if not self.enabled then return end
        self.now=self.now+math.max(0,math.min(1,tonumber(dt) or 0))
        if self.now < self.scanAt then return end
        self.scanAt=self.now+0.35
        if deps.isEntity and deps.isEntity() then
            self.status="Paused: fragment objective is survivor-only"
            return
        end
        local screens=guiRoots()
        if #screens>0 then
            local root=screens[1]
            if self.lastPuzzle~=root then
                self.lastPuzzle=root;self.puzzles=self.puzzles+1
                self.clickedSteps={}
            end
            local answer,buttonCount=answerFor(root)
            if not answer then
                self.unsupported=self.unsupported+1
                self.status="Puzzle visible: no explicit answer ("..buttonCount.." buttons)"
                return
            end
            local step=attr(root,"Stage") or attr(root,"Round")
                or attr(root,"PuzzleStep") or ""
            local signature=tostring(answer).."|"..buttonText(answer)
                .."|"..tostring(step)
            if self.clickedSteps[signature] then
                self.status="Answer sent; waiting for puzzle to advance"
                return
            end
            if self.clickButton and self.now-self.lastClick>=0.8 then
                local ok,result=pcall(self.clickButton,answer)
                if ok and result then
                    self.clicks=self.clicks+1
                    self.lastClick=self.now
                    self.clickedSteps[signature]=true
                    self.status="Puzzle answer clicked (client input; unverified)"
                    return
                end
            end
            self.status="Puzzle answer found; input unavailable"
            return
        end
        self.lastPuzzle=nil
        if self.now-self.lastPrompt>=2 then
            local found=candidates()
            if #found>0 then
                local prompt=found[1]
                if self.activatePrompt then
                    local ok,result=pcall(self.activatePrompt,prompt)
                    if ok and result then
                        self.prompts=self.prompts+1
                        self.attempted[prompt]=true
                        self.lastPrompt=self.now
                        self.status="Fragment interaction sent (not server-confirmed)"
                        return
                    end
                end
                self.status="Fragment in range; interaction API unavailable"
                return
            end
        end
        self.status="Waiting for an accessible Hotel fragment"
    end
    function self:Inspect()
        local rows={}
        local screens=guiRoots()
        rows[#rows+1]="[Zinc Mayhem] visible fragment puzzle GUIs: "..#screens
        for _,root in ipairs(screens) do
            local answer,count=answerFor(root)
            rows[#rows+1]="[Zinc Mayhem] puzzle="..root.Name
                .." buttons="..count.." explicitAnswer="..
                (answer and answer.Name or "(none)")
            local shown=0
            for _,button in ipairs(puzzleButtons(root)) do
                shown=shown+1
                rows[#rows+1]="[Zinc Mayhem] button "..button.Name
                    .." text="..buttonText(button)
                    .." correct="..tostring(attr(button,"IsCorrect"))
                if shown>=12 then break end
            end
        end
        rows[#rows+1]="[Zinc Mayhem] nearby fragment prompts: "..#candidates()
        return rows
    end
    function self:Status()
        return self.status.." | prompts "..self.prompts.." | clicks "..self.clicks
    end
    function self:Unload()self:SetEnabled(false)end
    return self
end
return Module
