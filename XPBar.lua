local BAR_WIDTH, BAR_HEIGHT = 600, 28

-- Colours taken from the Luxthos Experience Bar: |cFFFF9700 turn-in XP,
-- |cFF4F90FF rested. In-progress quest XP reuses the quest colour, faded.
local COL_XP = { 0.62, 0.30, 0.90 }
local COL_QUEST = { 1.00, 0.592, 0.00 }
local COL_RESTED = { 0.31, 0.565, 1.00 }

-- Mainline namespaces this; keep the bare global as a fallback.
local IsAtMaxLevel = (C_PlayerInfo and C_PlayerInfo.IsPlayerAtEffectiveMaxLevel) or IsPlayerAtEffectiveMaxLevel
local GetRewardXP = GetQuestLogRewardXP
local IsQuestComplete = C_QuestLog.IsComplete
local BigNum = BreakUpLargeNumbers or FormatLargeNumber or tostring

local db
local stats = { cur = 0, max = 0, rested = 0, turnIn = 0, inProgress = 0, quests = 0 }
local session = { started = false, start = 0, xp = 0, lastXP = 0, lastMax = 0, lastLevel = 0 }
local played = { total = 0, level = 0, at = 0 }

local function Locked()
	return not db or db.locked
end

local function AtMaxLevel()
	if IsAtMaxLevel then
		return IsAtMaxLevel()
	end
	return UnitLevel("player") >= GetMaxLevelForPlayerExpansion()
end

local function FormatTime(t)
	if t <= 59 then
		return "< 1m"
	end
	local d = math.floor(t / 86400)
	local h = math.floor(t % 86400 / 3600)
	local m = math.floor(t % 3600 / 60)
	if d > 0 then
		return format("%dd %dh %dm", d, h, m)
	elseif h > 0 then
		return format("%dh %dm", h, m)
	end
	return format("%dm", m)
end

local bar = CreateFrame("StatusBar", "XPBarFrame", UIParent)
bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
bar:SetPoint("TOP", UIParent, "TOP", 0, -24)
bar:SetMinMaxValues(0, 1)
bar:SetValue(0)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:SetFrameStrata("HIGH")
bar:EnableMouse(true) -- always on, for the tooltip; dragging is gated by Locked()
bar:RegisterForDrag("LeftButton")

-- black: unearned XP
local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 1)

-- purple: current XP
local fill = bar:CreateTexture(nil, "ARTWORK")
fill:SetColorTexture(1, 1, 1, 1)
bar:SetStatusBarTexture(fill)
bar:SetStatusBarColor(COL_XP[1], COL_XP[2], COL_XP[3])

-- orange: turn-in XP
local questTex = bar:CreateTexture(nil, "OVERLAY", nil, 1)
questTex:SetColorTexture(COL_QUEST[1], COL_QUEST[2], COL_QUEST[3], 0.95)
questTex:Hide()

-- faded orange: in-progress quest XP
local inProgressTex = bar:CreateTexture(nil, "OVERLAY", nil, 2)
inProgressTex:SetColorTexture(COL_QUEST[1], COL_QUEST[2], COL_QUEST[3], 0.40)
inProgressTex:Hide()

-- blue: rested pool
local restedTex = bar:CreateTexture(nil, "OVERLAY", nil, 3)
restedTex:SetColorTexture(COL_RESTED[1], COL_RESTED[2], COL_RESTED[3], 0.90)
restedTex:Hide()

-- additive spark at the current XP boundary, as the Luxthos bar has
local spark = bar:CreateTexture(nil, "OVERLAY", nil, 4)
spark:SetColorTexture(1, 1, 1, 0.6)
spark:SetBlendMode("ADD")
spark:Hide()

-- Reuse the game's own font file (Friz Quadrata) rather than a hardcoded path.
local FONT = GameFontNormal and GameFontNormal:GetFont()

-- WoW only offers OUTLINE and THICKOUTLINE, so the lightest edge available is
-- no outline at all, leaning on the shadow instead. Text inside the bar uses
-- that; text outside sits over the world and keeps the outline.
local function MakeText(size, flags)
	local fs = bar:CreateFontString(nil, "OVERLAY")
	if FONT then
		fs:SetFont(FONT, size, flags == nil and "OUTLINE" or flags)
	else
		fs:SetFontObject("GameFontHighlight")
	end
	fs:SetDrawLayer("OVERLAY", 7)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	return fs
end

-- above the bar
local levelTimeText = MakeText(12)
levelTimeText:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 5)

local sessionTimeText = MakeText(12)
sessionTimeText:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 5)

-- inside the bar, no outline
local levelText = MakeText(13, "")
levelText:SetPoint("LEFT", bar, "LEFT", 8, 0)

local mainText = MakeText(14, "")
mainText:SetPoint("CENTER", bar, "CENTER", 0, 0)

local pctText = MakeText(13, "")
pctText:SetPoint("RIGHT", bar, "RIGHT", -8, 0)

-- below the bar
local rateText = MakeText(12)
rateText:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -5)

local infoText = MakeText(12)
infoText:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -5)

-- Quest XP split into turn-in (ready to hand in) and in-progress.
local function QuestXP()
	if not GetRewardXP then
		return 0, 0, 0
	end
	local turnIn, inProgress, count = 0, 0, 0
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local reward = GetRewardXP(info.questID) or 0
			if reward > 0 then
				local done = (IsQuestComplete and IsQuestComplete(info.questID))
					or C_QuestLog.ReadyForTurnIn(info.questID)
				if done then
					turnIn = turnIn + reward
					count = count + 1
				else
					inProgress = inProgress + reward
				end
			end
		end
	end
	return turnIn, inProgress, count
end

local function SetSegment(tex, startVal, amount, max)
	if amount <= 0 then
		tex:Hide()
		return
	end
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", bar, "TOPLEFT", BAR_WIDTH * (startVal / max), 0)
	tex:SetSize(BAR_WIDTH * (amount / max), BAR_HEIGHT)
	tex:Show()
end

local function HideAll()
	questTex:Hide()
	inProgressTex:Hide()
	restedTex:Hide()
	spark:Hide()
	rateText:SetText("")
	infoText:SetText("")
end

-- Accumulate XP earned this session. A level-up is detected by the level
-- itself, not by XP going down: one gain can cross a level and still leave
-- more XP than before. That case counts the remainder of the old level plus
-- the carryover into the new one.
local function TrackXP(cur, max, level)
	if not session.started then
		return
	end
	if level > session.lastLevel then
		session.xp = session.xp + math.max(session.lastMax - session.lastXP, 0) + cur
	else
		session.xp = session.xp + math.max(cur - session.lastXP, 0)
	end
	session.lastXP, session.lastMax, session.lastLevel = cur, max or 0, level
end

local function PlayedTimes()
	if played.at <= 0 then
		return nil, nil
	end
	local since = GetTime() - played.at
	return played.total + since, played.level + since
end

local function UpdateRate()
	if not session.started then
		return
	end
	local secs = GetTime() - session.start
	sessionTimeText:SetFormattedText("Time this session: %s", FormatTime(secs))

	local totalTime, levelTime = PlayedTimes()
	if totalTime then
		if stats.max <= 0 then
			levelTimeText:SetFormattedText("Time played: %s", FormatTime(totalTime))
		else
			levelTimeText:SetFormattedText("Time this level: %s", FormatTime(levelTime))
		end
	else
		levelTimeText:SetText("")
	end

	if stats.max <= 0 or secs < 1 or session.xp <= 0 then
		rateText:SetText("")
		return
	end
	local hourly = math.ceil(session.xp / (secs / 3600))
	local remaining = stats.max - stats.cur
	local shown = hourly > 10000 and format("%.1fK", hourly / 1000) or BigNum(hourly)
	if hourly >= 1 and remaining > 0 then
		rateText:SetFormattedText("Leveling in: %s (%s XP/Hour)",
			FormatTime(math.ceil(remaining / hourly * 3600)), shown)
	else
		rateText:SetFormattedText("%s XP/Hour", shown)
	end
end

local function Update()
	local cur, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	TrackXP(cur, max, level)
	stats.cur, stats.max = cur, max or 0
	stats.rested, stats.turnIn, stats.inProgress, stats.quests = 0, 0, 0, 0

	if AtMaxLevel() or not max or max <= 0 then
		-- Stay visible while unlocked so the bar can still be positioned.
		stats.max = 0
		HideAll()
		if Locked() then
			bar:Hide()
		else
			bar:Show()
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(0)
			levelText:SetFormattedText("Level %d", level)
			mainText:SetText("Max Level")
			pctText:SetText("")
		end
		UpdateRate()
		return
	end

	bar:Show()
	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)

	local headroom = max - cur
	local turnIn, inProgress, quests = QuestXP()
	turnIn = math.min(turnIn, headroom)
	inProgress = math.min(inProgress, headroom - turnIn)
	-- the full pool is reported; only the drawn segment is clamped to what fits
	local rested = GetXPExhaustion() or 0
	stats.rested, stats.turnIn, stats.inProgress, stats.quests = rested, turnIn, inProgress, quests

	-- stacked in order, as the Luxthos bar does:
	-- fill, then turn-in XP, then in-progress quest XP, then rested
	SetSegment(questTex, cur, turnIn, max)
	SetSegment(inProgressTex, cur + turnIn, inProgress, max)
	SetSegment(restedTex, cur + turnIn + inProgress,
		math.min(rested, headroom - turnIn - inProgress), max)

	if cur > 0 then
		spark:ClearAllPoints()
		spark:SetPoint("TOPLEFT", bar, "TOPLEFT", BAR_WIDTH * (cur / max) - 1, 0)
		spark:SetSize(2, BAR_HEIGHT)
		spark:Show()
	else
		spark:Hide()
	end

	levelText:SetFormattedText("Level %d", level)
	mainText:SetFormattedText("%s / %s (%s)", BigNum(cur), BigNum(max), BigNum(headroom))
	if turnIn > 0 then
		pctText:SetFormattedText("%.1f%% (%.1f%%)", cur / max * 100, (cur + turnIn) / max * 100)
	else
		pctText:SetFormattedText("%.1f%%", cur / max * 100)
	end
	-- "Completed" is the Luxthos wording for turn-in XP
	infoText:SetFormattedText(
		"Completed: |cFFFF9700%.1f%%|r - Rested: |cFF4F90FF%.1f%%|r",
		turnIn / max * 100, rested / max * 100)

	UpdateRate()
end

local function Init()
	XPBarDB = XPBarDB or {}
	db = XPBarDB
	if db.locked == nil then
		db.locked = true
	end
	if db.point then
		bar:ClearAllPoints()
		bar:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
	end
	-- PLAYER_ENTERING_WORLD also fires on every loading screen, so the session
	-- baseline is only taken once.
	if not session.started then
		session.started = true
		session.start = GetTime()
		session.xp = 0
		session.lastXP = UnitXP("player")
		session.lastMax = UnitXPMax("player") or 0
		session.lastLevel = UnitLevel("player")
		if RequestTimePlayed and C_Timer then
			C_Timer.After(0.5, function() RequestTimePlayed() end)
		end
	end
end

-- Only the clock-driven lines need this; it is throttled and skips the quest scan.
local throttle = 0
bar:SetScript("OnUpdate", function(self, e)
	throttle = throttle + e
	if throttle >= 1 then
		throttle = 0
		UpdateRate()
	end
end)

bar:SetScript("OnEnter", function(self)
	Update()
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("XPBar")
	if stats.max <= 0 then
		GameTooltip:AddLine("Max level", 0.6, 0.6, 0.6)
	else
		GameTooltip:AddDoubleLine("Experience",
			format("%s / %s (%.1f%%)", BigNum(stats.cur), BigNum(stats.max),
				stats.cur / stats.max * 100), 1, 1, 1, COL_XP[1], COL_XP[2], COL_XP[3])
		GameTooltip:AddDoubleLine("To next level",
			BigNum(stats.max - stats.cur), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Rested",
			stats.rested > 0 and BigNum(stats.rested) or "none",
			1, 1, 1, COL_RESTED[1], COL_RESTED[2], COL_RESTED[3])
		GameTooltip:AddDoubleLine("Quests ready to turn in",
			format("%d  (+%s XP)", stats.quests, BigNum(stats.turnIn)),
			1, 1, 1, COL_QUEST[1], COL_QUEST[2], COL_QUEST[3])
		GameTooltip:AddDoubleLine("Quests in progress",
			format("+%s XP", BigNum(stats.inProgress)),
			1, 1, 1, COL_QUEST[1], COL_QUEST[2], COL_QUEST[3])
		GameTooltip:AddDoubleLine("Earned this session", BigNum(session.xp), 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(Locked() and "/xpbar unlock to move" or "Drag to move", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end)

bar:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

bar:SetScript("OnDragStart", function(self)
	if not Locked() then
		self:StartMoving()
	end
end)

bar:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relPoint, x, y = self:GetPoint()
	db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end)

bar:SetScript("OnEvent", function(self, event, a1, a2)
	if event == "PLAYER_ENTERING_WORLD" then
		Init()
	elseif event == "TIME_PLAYED_MSG" then
		played.total, played.level, played.at = a1 or 0, a2 or 0, GetTime()
		UpdateRate()
		return
	elseif event == "PLAYER_LEVEL_UP" and played.at > 0 then
		-- time at level restarts; total keeps accruing
		played.total = played.total + (GetTime() - played.at)
		played.level = 0
		played.at = GetTime()
	end
	Update()
end)

bar:RegisterEvent("PLAYER_ENTERING_WORLD")
bar:RegisterEvent("PLAYER_XP_UPDATE")
bar:RegisterEvent("PLAYER_LEVEL_UP")
bar:RegisterEvent("UPDATE_EXHAUSTION")
bar:RegisterEvent("QUEST_LOG_UPDATE")
bar:RegisterEvent("TIME_PLAYED_MSG")

SLASH_XPBAR1 = "/xpbar"
SlashCmdList.XPBAR = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "lock" then
		db.locked = true
	elseif msg == "unlock" then
		db.locked = false
	elseif msg == "debug" then
		print(format("XPBar: xp=%d/%d rested=%d turnIn=%d inProgress=%d quests=%d session=%d played=%s rewardXPfn=%s isCompletefn=%s",
			stats.cur, stats.max, stats.rested, stats.turnIn, stats.inProgress, stats.quests,
			session.xp, tostring(played.at > 0),
			tostring(GetRewardXP ~= nil), tostring(IsQuestComplete ~= nil)))
		return
	elseif msg == "reset" then
		db.point, db.relPoint, db.x, db.y = nil, nil, nil, nil
		bar:ClearAllPoints()
		bar:SetPoint("TOP", UIParent, "TOP", 0, -24)
		print("XPBar: position reset")
		return
	else
		print("XPBar: /xpbar lock | unlock | reset | debug")
		return
	end
	Update()
	print("XPBar: " .. (db.locked and "locked" or "unlocked - drag to move"))
end
