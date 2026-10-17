-- Actual MAYHEM Player ESP role/rig filter regression (pure Lua 5.4).
local file=assert(io.open("doors_mayhem.lua","rb"))
local source=file:read("*a");file:close()
local first=assert(source:find("local ENTITY_ROLE = {",1,true))
local last=assert(source:find("\nlocal fragmentAliases = {}",first,true))
local section=source:sub(first,last-1)
local env=[[
local function norm(text) return tostring(text or ""):lower():gsub("[^%w]","") end
]]
local chunk=assert(load(env..section..
    "\nreturn roleOf, playerESPRelation, playerESPPart\n","@player_esp"))
local role,relation,part=chunk()
local entityTeam={Name="Entities"}
local survivorTeam={Name="Survivors"}
local function mockCharacter(name, opts)
    opts=opts or {}
    local c={Name=name or "Character",PrimaryPart=opts.primary,
        attributes=opts.attributes or {}, Humanoid=opts.hum,
        HumanoidRootPart=opts.root, descendant=opts.descendant}
    function c:GetAttribute(key)return self.attributes[key]end
    function c:FindFirstChildOfClass(class)
        return class=="Humanoid" and self.Humanoid or nil
    end
    function c:FindFirstChild(key)
        return key=="HumanoidRootPart" and self.HumanoidRootPart or nil
    end
    function c:FindFirstChildWhichIsA(key)
        return key=="BasePart" and self.descendant or nil
    end
    return c
end
local function mockPlayer(name, team, attrs, char)
    local p={Name=name,Team=team,attributes=attrs or {},Character=char}
    function p:GetAttribute(key) return self.attributes[key] end
    return p
end
local root={Position={X=10}}
local localPlayer=mockPlayer("Me",entityTeam,{SelectedEntity="Rush"},
    mockCharacter("Me",{root=root,hum={Health=100}}))
local survivor=mockPlayer("Survivor",survivorTeam,{SelectedEntity="Figure"},
    mockCharacter("Survivor",{root=root,hum={Health=90},
        attributes={CurrentEntity="Rush"}}))
assert(role(localPlayer)=="Entity")
assert(role(survivor)=="Survivor",
    "team survivor must override stale entity character/player attributes")
local visible,kind=relation(localPlayer,survivor,true)
assert(visible and kind=="enemy","entity should ESP an opposite-team survivor")
local teammate=mockPlayer("Friend",entityTeam,{},
    mockCharacter("Friend",{root=root,hum={Health=100}}))
local ok,teamRelation=relation(localPlayer,teammate,true)
assert(not ok and teamRelation=="teammate")
local showAll,friendRelation=relation(localPlayer,teammate,false)
assert(showAll and friendRelation=="friend")
local otherEntity=mockPlayer("OtherEntity",{Name="Monsters"},{Role="Figure"},
    mockCharacter("OtherEntity",{root=root,hum={Health=100}}))
local x=relation(localPlayer,otherEntity,true)
assert(not x,"other entity should not be mistaken for a survivor")
local unknownPlayer=mockPlayer("Unknown",{Name="Lobby"},{},
    mockCharacter("Unknown",{root=root,hum={Health=100}}))
local unk,category=relation(localPlayer,unknownPlayer,true)
assert(unk and category=="neutral",
    "unknown players on another team should still show cyan")
local nosource=mockPlayer("UnknownNoTeam",nil,{},
    mockCharacter("UnknownNoTeam",{root=root,hum={Health=100}}))
assert(select(1,relation(localPlayer,nosource,true)))
assert(not select(1,relation(localPlayer,localPlayer,false)),
    "self must never appear in player ESP")
local custom=mockCharacter("CustomEntityRig",{primary=root,attributes={}})
local actual,description=part(custom)
assert(actual==root and description=="custom rig",
    "custom playable entity character without Humanoid must be eligible")
local descendant={Position={X=1}}
local nested=mockCharacter("Nested",{descendant=descendant})
assert(part(nested)==descendant,"deep BasePart fallback should work")
assert(part(mockCharacter("Dead",{root=root,hum={Health=0}}))==nil)
assert(part(mockCharacter("DeadAttribute",{root=root,
    attributes={IsDead=true}}))==nil)
assert(part(mockCharacter("NoParts"))==nil)
print("mayhem entity-side player ESP: survivor targeting, teams, unknown roles, custom rigs OK")
