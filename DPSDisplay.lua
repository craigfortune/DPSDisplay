-----------------------------------------------------------------------------------------------
-- Client Lua Script for DPSDisplay
-- Copyright (c) NCsoft. All rights reserved

-- Version 1.1

-----------------------------------------------------------------------------------------------
 
require "Window"
require "ChatSystemLib"
 
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
		Apollo.RegisterSlashCommand("dpsD", "OnDPSDisplay", self)
		self.timer = ApolloTimer.Create(0.2, true, "OnTimer", self)
		
		Apollo.RegisterEventHandler("CombatLogDamage", "onDamageDone", self)
		
		-----
		
		Apollo.RegisterEventHandler("DamageOrHealingDone",		"OnDamageOrHealing", self)
		Apollo.RegisterEventHandler("CombatLogTransference", 	"OnCombatLogTransference", self)
		
		self:setup()
		
		self:OnTimer() -- Force an update
		self.wndMain:Invoke()
	end
end

-----------------------------------------------------------------------------------------------
-- DPSDisplay Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

function DPSDisplay:setup()

	print("setup")

	self.dpsText = self.wndMain:FindChild("dpsText")
	self.dpsVals = self.wndMain:FindChild("dpsVals")
	self.dpstimeWindowText = self.wndMain:FindChild("timeWindowText")

	self.dmg = 0
	self.highestDmg = 0
	self.highestCrit = 0
	self.highestNonCrit = 0
	
	self.highestDPS = 0		
	self.dmgReadings = {}
	
	self.timeWindow = 10
end

-- on Slash "dpsD"
function DPSDisplay:OnDPSDisplay(strCmd, strArg)

	if strArg == "" then
		self:OnToggleDPSDisplay()
	else
		local args = {}
		for arg in strArg:gmatch("%S+") do table.insert(args, arg) end

		if args[1] == "timewindow" and args[2] then
			self:setTimeWindow(args[2])			
		elseif args[1] == "help" then
			self:displayHelp()
		else
			-- default catch if we don't know what the user entered
			local strError = "DPSDisplay: Command <" .. args[1] .. "> not understood. Type /dpsD help for available commands"
			ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Debug, strError, "")
		end				
	end
end

function DPSDisplay:displayHelp()
	local strHelp = [[
			
	/dpsD - Toggles visibility of the DPS DPSDisplay
	/dpsD timewindow 10 - Sets the time window to 10 seconds
	/dpsD help - Displays this help text
	]]
	ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Debug, strHelp, "")
end

function DPSDisplay:setTimeWindow(timeWindowValue)	
	local tmpTimeWindow = tonumber(timeWindowValue)
	
	if tmpTimeWindow < 1 or tmpTimeWindow > 20 then
		local strConfirmation = "DPSDisplay: Please enter a value between 1 and 20"	
		ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Debug, strConfirmation, "")
	else
		self.timeWindow = tmpTimeWindow
		local strConfirmation = "DPSDisplay: Updated timeWindow to " .. self.timeWindow .. " seconds."	
		ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Debug, strConfirmation, "")
	end
		
	-- Clear out the current ones so we don't get some funkiness going on
	for k,v in pairs(self.dmgReadings) do
		self.dmgReadings[k] = nil
	end							
end

-------------------------

function DPSDisplay:OnToggleDPSDisplay()
	if self.wndMain:IsVisible() then
		self.wndMain:Show(false)
	else
		self.wndMain:Show(true)
	end
end

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
		
		local currDPS = self:getCurrentDPS()
		if currDPS <= 0 then
			currDPS = 0
		end

		local highDPS = self:getHighestDPS()
		if highDPS <= 0 then
			highDPS = 0
		end
							
		self.dpsVals:SetText(
								self.dmg
								.. "\n" .. self:getHighestDamage()
								.. "\n" .. self:getHighestCrit()
								.. "\n" .. self:getHighestNonCrit()
								.. "\n" .. math.floor(currDPS)
								.. "\n" .. math.floor(highDPS)
							)
							
		self.dpstimeWindowText:SetText("( Time window: " .. self.timeWindow .. " seconds )")

	end
end

function DPSDisplay:addDamageReading(dmg, crit)
	self.dmg = dmg	
	dmgData = 	{
					dmg = dmg,
					timestamp = os.clock()
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
	local i = 1
	for k,v in pairs(self.dmgReadings) do
		local timeStamp = self.dmgReadings[i].timestamp
		if(os.clock() - self.dmgReadings[i].timestamp) > self.timeWindow then
			table.remove(self.dmgReadings, i)
		else
			i = i + 1
		end	
	end
end

function DPSDisplay:getCurrentDPS()

	if(#self.dmgReadings < 2) then
		return 0
	end

	dmgSum = 0
	local oldestTime = 0
	local newestTime = 0
	
	for k,v in pairs(self.dmgReadings) do
		if oldestTime == 0 then
			oldestTime = v.timestamp
		end
		
		local dmgReading = v.dmg
		dmgSum = dmgSum + dmgReading
		
		newestTime = v.timestamp
	end

	rangeOfTime = newestTime - oldestTime
	rangeOfTime = self.timeWindow
	if rangeOfTime > 0 then
		dps = (dmgSum / rangeOfTime)
	else
		dps = 0
	end
	
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
