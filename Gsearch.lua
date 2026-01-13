GSEARCH_GUILD_QUERY = GSEARCH_GUILD_QUERY or "";
GSEARCH_GUILD_INDEX_MAP = GSEARCH_GUILD_INDEX_MAP or {};

local orig_GetNumGuildMembers = nil;
local orig_GetGuildRosterInfo = nil;
local orig_GetGuildRosterLastOnline = nil;

local function Gsearch_SafeLower(s)
	if not s then return ""; end
	return string.lower(s);
end

local function Gsearch_MatchName(name, needle)
	if not needle or needle == "" then return true; end
	name = Gsearch_SafeLower(name);
	needle = Gsearch_SafeLower(needle);
	return string.find(name, needle, 1, true) ~= nil;
end

local function Gsearch_RequestRoster()
	if IsInGuild and not IsInGuild() then
		return;
	end
	if GuildRoster then
		GuildRoster();
	end
end

local function Gsearch_GetQuery()
	if not GsearchGuildSearchBox then return ""; end
	local q = GsearchGuildSearchBox:GetText() or "";
	q = string.gsub(q, "^%s+", "");
	q = string.gsub(q, "%s+$", "");
	return q;
end

local function Gsearch_IsFiltering()
	if not GuildFrame or not GuildFrame:IsShown() then return false; end
	local q = Gsearch_GetQuery();
	return q ~= nil and q ~= "";
end

local function Gsearch_FindFirstExistingGlobal(names)
	for i = 1, table.getn(names) do
		local v = getglobal(names[i]);
		if v then return v; end
	end
	return nil;
end

local function Gsearch_GetRosterUI()
	local scroll = Gsearch_FindFirstExistingGlobal({
		"GuildRosterScrollFrame",
		"GuildRosterFrameScrollFrame",
		"GuildFrameGuildListScrollFrame",
		"GuildRosterContainerScrollFrame",
	});

	local prefixes = {
		"GuildRosterButton",
		"GuildRosterContainerButton",
		"GuildRosterFrameButton",
		"GuildFrameButton",
	};

	for p = 1, table.getn(prefixes) do
		local first = getglobal(prefixes[p] .. "1");
		if first then
			return scroll, prefixes[p];
		end
	end

	return scroll, nil;
end

local function Gsearch_ForceGuildRosterRefresh()
	-- 1) Ask the stock UI to update if possible
	-- IMPORTANT: Do not call these while the frame is hidden; some client UIs will reopen.
	if FriendsFrame and FriendsFrame.IsShown and FriendsFrame:IsShown() then
		if FriendsFrame_Update then
			FriendsFrame_Update();
		end
	end
	if GuildFrame and GuildFrame.IsShown and GuildFrame:IsShown() then
		if GuildRoster_Update then
			GuildRoster_Update();
		elseif GuildRosterFrame_Update then
			GuildRosterFrame_Update();
		elseif GuildFrame_Update then
			GuildFrame_Update();
		end
	end

	-- 2) If we're filtering, aggressively hide any extra buttons so stale names don't remain
	if not Gsearch_IsFiltering() then
		return;
	end

	local scroll, prefix = Gsearch_GetRosterUI();
	if not prefix then
		return;
	end

	local num = 0;
	if GetNumGuildMembers then
		num = GetNumGuildMembers();
	end

	-- If we can, keep the scroll frame in sync too
	if scroll and FauxScrollFrame_Update then
		local visible = 0;
		for i = 1, 40 do
			if getglobal(prefix .. i) then
				visible = i;
			else
				break;
			end
		end
		local first = getglobal(prefix .. "1");
		local height = 16;
		if first and first.GetHeight then
			height = first:GetHeight();
		end
		FauxScrollFrame_Update(scroll, num, visible, height);
		if scroll.UpdateScrollChildRect then
			scroll:UpdateScrollChildRect();
		end
	end

	for i = 1, 40 do
		local btn = getglobal(prefix .. i);
		if not btn then break; end
		-- The stock UI should hide these, but some builds leave stale text; enforce hide.
		local index = nil;
		if scroll and FauxScrollFrame_GetOffset then
			index = FauxScrollFrame_GetOffset(scroll) + i;
		else
			index = i;
		end
		if index > num then
			btn:Hide();
		else
			btn:Show();
		end
	end
end

local function Gsearch_RebuildIndexMap()
	GSEARCH_GUILD_INDEX_MAP = {};
	local q = Gsearch_GetQuery();
	GSEARCH_GUILD_QUERY = q;

	if not q or q == "" then
		return;
	end
	if IsInGuild and not IsInGuild() then
		return;
	end
	if not orig_GetNumGuildMembers or not orig_GetGuildRosterInfo then
		return;
	end

	local total = orig_GetNumGuildMembers();
	for i = 1, total do
		local name = orig_GetGuildRosterInfo(i);
		if name and Gsearch_MatchName(name, q) then
			tinsert(GSEARCH_GUILD_INDEX_MAP, i);
		end
	end
end

local function Gsearch_ClearInvalidSelection()
	if not Gsearch_IsFiltering() then
		return;
	end
	local count = table.getn(GSEARCH_GUILD_INDEX_MAP);
	if GuildFrame and GuildFrame.selectedGuildMember then
		if count == 0 or GuildFrame.selectedGuildMember > count then
			GuildFrame.selectedGuildMember = 0;
		end
	end
end


function GsearchGuild_PerformFilter()
	Gsearch_RebuildIndexMap();
	Gsearch_ClearInvalidSelection();
	Gsearch_ForceGuildRosterRefresh();
end

function GsearchGuild_BuildUI()
	if not GuildFrame then return; end
	if GsearchGuildSearchBox then return; end

	-- Search box in the Guild UI
	local eb = CreateFrame("EditBox", "GsearchGuildSearchBox", GuildFrame, "InputBoxTemplate");
	eb:SetAutoFocus(false);
	eb:SetWidth(130);
	eb:SetHeight(18);

	local label = GuildFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
	label:SetPoint("TOPLEFT", GuildFrame, "TOPLEFT", 24, -60);
	label:SetText("Search:");

	eb:SetPoint("LEFT", label, "RIGHT", 6, 0);
	eb:SetText("");
	eb:SetScript("OnTextChanged", function()
		Gsearch_RequestRoster();
		GsearchGuild_PerformFilter();
	end);
	eb:SetScript("OnEnterPressed", function()
		this:ClearFocus();
	end);
	eb:SetScript("OnEscapePressed", function()
		this:SetText("");
		this:ClearFocus();
		GsearchGuild_PerformFilter();
	end);

	-- Keep list fresh when opening the Guild UI
	local oldOnShow = GuildFrame:GetScript("OnShow");
	GuildFrame:SetScript("OnShow", function()
		if oldOnShow then oldOnShow(); end
		Gsearch_RequestRoster();
		GsearchGuild_PerformFilter();
	end);
end

local function Gsearch_InstallWrappers()
	if orig_GetNumGuildMembers then return; end
	if not GetNumGuildMembers or not GetGuildRosterInfo then return; end

	orig_GetNumGuildMembers = GetNumGuildMembers;
	orig_GetGuildRosterInfo = GetGuildRosterInfo;
	orig_GetGuildRosterLastOnline = GetGuildRosterLastOnline;

	GetNumGuildMembers = function()
		if Gsearch_IsFiltering() then
			return table.getn(GSEARCH_GUILD_INDEX_MAP);
		end
		return orig_GetNumGuildMembers();
	end

	GetGuildRosterInfo = function(index)
		if Gsearch_IsFiltering() then
			local mapped = GSEARCH_GUILD_INDEX_MAP[index];
			if not mapped then
				-- Some stock UI code doesn't guard nil returns (e.g. concatenating level).
				return "", "", 0, 0, "", "", "", "", false, "";
			end
			return orig_GetGuildRosterInfo(mapped);
		end
		return orig_GetGuildRosterInfo(index);
	end

	if orig_GetGuildRosterLastOnline then
		GetGuildRosterLastOnline = function(index)
			if Gsearch_IsFiltering() then
				local mapped = GSEARCH_GUILD_INDEX_MAP[index];
				if not mapped then
					return 0, 0, 0, 0;
				end
				return orig_GetGuildRosterLastOnline(mapped);
			end
			return orig_GetGuildRosterLastOnline(index);
		end
	end
end

-- Bootstrap
local gsearchEventFrame = CreateFrame("Frame", "GsearchEventFrame");
gsearchEventFrame:RegisterEvent("PLAYER_LOGIN");
gsearchEventFrame:RegisterEvent("GUILD_ROSTER_UPDATE");
gsearchEventFrame:RegisterEvent("PLAYER_GUILD_UPDATE");
gsearchEventFrame:SetScript("OnEvent", function()
	if event == "PLAYER_LOGIN" then
		Gsearch_InstallWrappers();
		GsearchGuild_BuildUI();
		Gsearch_RequestRoster();
		return;
	end

	if event == "PLAYER_GUILD_UPDATE" then
		Gsearch_RequestRoster();
		if GuildFrame and GuildFrame.IsShown and GuildFrame:IsShown() then
			GsearchGuild_PerformFilter();
		end
		return;
	end

	if event == "GUILD_ROSTER_UPDATE" then
		-- Only refresh filtered UI when the Guild UI is currently open.
		if Gsearch_IsFiltering() then
			GsearchGuild_PerformFilter();
		end
	end
end);

-- Optional: slash command to open Guild UI and focus search
SlashCmdList["GSEARCH"] = function(msg)
	if ToggleGuildFrame then
		ToggleGuildFrame();
	end
	if GsearchGuildSearchBox then
		GsearchGuildSearchBox:SetFocus();
		GsearchGuildSearchBox:HighlightText();
	end
end
SLASH_GSEARCH1 = "/gsearch";
SLASH_GSEARCH2 = "/gs";
