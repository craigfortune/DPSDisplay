-----------------------------------------------------------------------------------------------
-- Client Lua Script for DPSDisplay
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
 
-----------------------------------------------------------------------------------------------
-- DPSDisplay Module Definition
-----------------------------------------------------------------------------------------------
local DPSDisplay = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function DPSDisplay:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here

    return o
end

function DPSDisplay:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end

-----------------------------------------------------------------------------------------------
-- DPSDisplay OnLoad
-----------------------------------------------------------------------------------------------
function DPSDisplay:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("DPSDisplay.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- DPSDisplay OnDocLoaded
-----------------------------------------------------------------------------------------------
function DPSDisplay:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "DPSDisplayForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
	    self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("dpsD", "OnDPSDisplayOn", self)
		self.timer = ApolloTimer.Create(0.4, true, "OnTimer", self)
		
		Apollo.RegisterEventHandler("CombatLogDamage", "onDamageDone", self)
		
		-----
		
		Apollo.RegisterEventHandler("DamageOrHealingDone",		"OnDamageOrHealing", self)
		Apollo.RegisterEventHandler("CombatLogTransference", 	"OnCombatLogTransference", self)
		
		self.dpsText = self.wndMain:FindChild("dpsText")
		self.dpsVals = self.wndMain:FindChild("dpsVals")

		self.dmg = 0
		self.highestDmg = 0
		self.highestCrit = 0
		self.highestNonCrit = 0
		
		self.highestDPS = 0		
		self.dmgReadings = {}
		
		self.timeWindow = 3
		
		self:OnTimer() -- Force an update
		self.wndMain:Invoke()
	end
end

-----------------------------------------------------------------------------------------------
-- DPSDisplay Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/dpsD"
function DPSDisplay:OnDPSDisplayOn()
	self.wndMain:Invoke() -- show the window
end

-- on timer
function DPSDisplay:OnTimer()
	self:pruneDamageList()
	self:updateTextDisplay()
end


-----------------------------------------------------------------------------------------------
-- DPSDisplayForm Functions
-----------------------------------------------------------------------------------------------
-- when the OK button is clicked
function DPSDisplay:OnOK()
	self.wndMain:Close() -- hide the window
end

-- when the Cancel button is clicked
function DPSDisplay:OnCancel()
	self.wndMain:Close() -- hide the window
end

---------------

function DPSDisplay:OnCombatLogTransference(tEventArgs)
	local bCritical = tEventArgs.eCombatResult == GameLib.CodeEnumCombatResult.Critical
	
	self:OnDamageOrHealing( tEventArgs.unitCaster, tEventArgs.unitTarget, tEventArgs.eDamageType, tEventArgs.nDamageAmount, tEventArgs.RawDamage, 0, 0, bCritical)
end

function DPSDisplay:OnDamageOrHealing( unitCaster, unitTarget, eDamageType, nDamage, nShieldDamaged, nAbsorptionAmount, bCritical)
	
	if eDamageType == GameLib.CodeEnumDamageType.Heal then
		return
	end
	if eDamageType == GameLib.CodeEnumDamageType.HealShields then
		return
	end
	
	if unitCaster == GameLib.GetPlayerUnit() then
		-- If the shield isn't damaged, then it gets passed as nil and not 0?
		if nShieldDamaged == nil then
			self:addDamageReading(nDamage, bCritical)
		else
			self:addDamageReading(nDamage + nShieldDamaged, bCritical)
		end
	end
end

---------------

function DPSDisplay:updateTextDisplay()
	--self.wndMain:SetText("Damage: " .. self.dmg)
	if(self.dpsText) then
		self.dpsText:SetText(
								"Last Damage: "
								.. "\nHighest Damage:  "
								.. "\nHighest Crit:  "
								.. "\nHighest Non-Crit:  "
								.. "\nCurrent DPS:  "
								.. "\nHighest DPS:  "
							)
							
		self.dpsVals:SetText(
								self.dmg
								.. "\n" .. self:getHighestDamage()
								.. "\n" .. self:getHighestCrit()
								.. "\n" .. self:getHighestNonCrit()
								.. "\n" .. self:getCurrentDPS()
								.. "\n" .. self:getHighestDPS()
							)

	end
end

function DPSDisplay:addDamageReading(dmg, crit)
	self.dmg = dmg	
	dmgData = 	{
					dmg = dmg,
					timestamp = os.time()
				}
	
	table.insert(self.dmgReadings, dmgData) -- add to end of the list
	
	if dmg > self.highestDmg then
		self.highestDmg = dmg
	end
	
	if crit == true then
		if dmg > self.highestCrit then
			self.highestCrit = dmg
		end
	else
		if dmg > self.highestNonCrit then
			self.highestNonCrit = dmg
		end
	end
end

function DPSDisplay:pruneDamageList()
	for k,v in pairs(self.dmgReadings) do
		local timestamp = v.timestamp
		if(os.difftime(os.time(), timestamp) > self.timeWindow) then
			self.dmgReadings[k] = nil
		end
	end

end

function DPSDisplay:getCurrentDPS()
	dmgSum = 0
	for k,v in pairs(self.dmgReadings) do
		local dmgReading = v.dmg
		dmgSum = dmgSum + dmgReading
	end
	
	dps = math.floor(dmgSum / self.timeWindow)
	if dps > self.highestDPS then
		self.highestDPS = dps
	end
	return dps
end

function DPSDisplay:getHighestDPS()
	return self.highestDPS
end

function DPSDisplay:getHighestDamage()
	return self.highestDmg
end

function DPSDisplay:getHighestCrit()
	return self.highestCrit
end

function DPSDisplay:getHighestNonCrit()
	return self.highestNonCrit
end

-----------------------------------------------------------------------------------------------
-- DPSDisplay Instance
-----------------------------------------------------------------------------------------------
local DPSDisplayInst = DPSDisplay:new()
DPSDisplayInst:Init()
