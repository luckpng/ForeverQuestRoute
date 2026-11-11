local _, A = ...
local ROWS, WIDTH, HEIGHT = 4, 340, 456
local anchors = {TOP=true, TOPLEFT=true, TOPRIGHT=true, LEFT=true, CENTER=true,
    RIGHT=true, BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true}
local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function label(parent, font, x, y, width)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, y); text:SetWidth(width); text:SetJustifyH("LEFT")
    return text
end

function A:SetTrackerLocked(locked)
    self.db.options.trackerLocked = locked == true
    if self.trackerFrame then self.trackerFrame:SetMovable(not self.db.options.trackerLocked) end
    if self.trackerLock then self.trackerLock:SetText(self.db.options.trackerLocked and "Destravar" or "Travar") end
end

function A:ApplyTrackerScale()
    if not self.trackerFrame or not self.trackerFrame.SetScale then return end
    local scale = 1
    if UIParent and UIParent.GetWidth and UIParent.GetHeight then
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        if finite(width) and finite(height) and width > 0 and height > 0 then
            scale = math.min(scale, (width-24)/WIDTH, (height-24)/HEIGHT)
        end
    end
    self.trackerFrame:SetScale(math.max(.35, scale))
end

function A:RestoreTrackerPosition()
    if not self.trackerFrame then return end
    local guid = type(UnitGUID) == "function" and UnitGUID("player")
    local store = self.Tracker:Store()
    if not guid or not store then return end
    local p = store.position
    self.trackerFrame:ClearAllPoints()
    if type(p) == "table" and anchors[p[1]] and anchors[p[2]] and finite(p[3]) and finite(p[4])
        and math.abs(p[3]) <= 10000 and math.abs(p[4]) <= 10000 then
        self.trackerFrame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        store.position = nil
        self.trackerFrame:SetPoint("RIGHT", UIParent, "RIGHT", -30, 0)
    end
    self.trackerCharacter = guid
    self.trackerPage = 1
end

function A:ToggleTracker()
    self.db.options.trackerVisible = not self.db.options.trackerVisible
    if self.trackerFrame then
        self.trackerFrame:SetShown(self.db.options.trackerVisible)
        self:RenderTracker()
    end
end

function A:ResetTrackerPosition()
    local store = self.Tracker:Store()
    if store then store.position = nil end
    if self.trackerFrame then
        self.trackerFrame:ClearAllPoints()
        self.trackerFrame:SetPoint("RIGHT", UIParent, "RIGHT", -30, 0)
    end
end

function A:CreateTrackerUI()
    if self.trackerFrame then return end
    local f = CreateFrame("Frame", "ForeverQuestRouteTracker", UIParent, "BasicFrameTemplateWithInset")
    self.trackerFrame = f
    f:SetSize(WIDTH, HEIGHT); f:SetPoint("RIGHT", UIParent, "RIGHT", -30, 0)
    f:SetClampedToScreen(true); f:EnableMouse(true)
    f.TitleText:SetText("Forever Quest Route  |  Diario")
    self:ApplyTrackerScale()
    self:RestoreTrackerPosition()
    -- Only the title region starts a drag; clicking objectives never moves the HUD.
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", 5, -2); drag:SetSize(WIDTH-40, 24)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        if not self.db.options.trackerLocked then f:StartMoving() end
    end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local data = self.Tracker:Store()
        if data and f.GetPoint then
            local point, _, relative, x, y = f:GetPoint()
            data.position = {point, relative, x, y}
        end
    end)
    f:SetScript("OnHide", function()
        -- Hiding UIParent (for example with Alt+Z) also invokes OnHide on its
        -- children. Preserve the preference unless this frame was hidden itself.
        if not f:IsShown() then self.db.options.trackerVisible = false end
    end)
    local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    open:SetPoint("TOPLEFT", 12, -29); open:SetSize(190, 22); open:SetText("Abrir diario completo")
    open:SetScript("OnClick", function() self:SelectTab("tracker"); self.frame:Show() end)
    local lock = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    lock:SetPoint("TOPLEFT", 212, -29); lock:SetSize(112, 22)
    lock:SetScript("OnClick", function() self:SetTrackerLocked(not self.db.options.trackerLocked) end)
    self.trackerLock = lock
    self.trackerSummary = label(f, "GameFontHighlightSmall", 14, -59, WIDTH-28)
    self.trackerRows = {}
    for i=1,ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT", 10, -83-(i-1)*79); row:SetSize(WIDTH-20, 76)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        row.title = label(row, "GameFontNormal", 4, -2, WIDTH-30); row.title:SetMaxLines(1)
        row.progress = label(row, "GameFontHighlightSmall", 4, -20, WIDTH-30); row.progress:SetMaxLines(1)
        row.objectives = label(row, "GameFontHighlightSmall", 10, -37, WIDTH-38); row.objectives:SetMaxLines(3)
        local bar = CreateFrame("StatusBar", nil, row)
        if bar.SetMinMaxValues and bar.SetValue and bar.SetStatusBarTexture then
            bar:SetPoint("TOPLEFT", 4, -75); bar:SetSize(WIDTH-30, 2)
            bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            bar:SetMinMaxValues(0, 100)
            if bar.SetStatusBarColor then bar:SetStatusBarColor(.38, .85, .7) end
            row.bar = bar
        else bar:Hide() end
        row:SetScript("OnClick", function(button, mouse)
            local entry = button.entry
            if not entry then return end
            if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
                self.Tracker:ToggleFavorite(entry.quest.id); self:Refresh(); return
            end
            self.Tracker:SetFocus(entry.quest.id)
            self.trackerPage = 1
            if mouse == "RightButton" then
                if self.OpenJournalQuest then self:OpenJournalQuest(entry.quest.id)
                else self:SelectTab("tracker"); self.selected = entry; self:Render(); self.frame:Show() end
            elseif entry.point then self:Navigate(entry.point)
            else self:Print("Objetivo sem coordenadas. Abra o diario para conferir os detalhes.") end
            if self.Refresh then self:Refresh() else self:RenderTracker() end
        end)
        row:SetScript("OnEnter", function(button)
            local entry = button.entry
            if not entry or not GameTooltip then return end
            GameTooltip:SetOwner(button, "ANCHOR_LEFT"); GameTooltip:SetText(entry.quest.title)
            GameTooltip:AddLine(entry.reason, 1, 1, 1, true)
            for _, objective in ipairs(entry.quest.objectives) do
                GameTooltip:AddLine((objective.finished and "[OK] " or "[ ] ") .. objective.text, 1, 1, 1, true)
            end
            GameTooltip:AddLine("Clique: focar e marcar destino. Botao direito: detalhes.", .7, .7, .7, true)
            GameTooltip:AddLine("Shift+clique: alternar favorito.", .7, .7, .7, true); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        self.trackerRows[i] = row
    end
    self.trackerFooter = label(f, "GameFontDisableSmall", 14, -405, WIDTH-28)
    local previous = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    previous:SetPoint("TOPLEFT", 12, -427); previous:SetSize(92, 22); previous:SetText("< Anterior")
    previous:SetScript("OnClick", function() self.trackerPage = math.max(1, (self.trackerPage or 1)-1); self:RenderTracker() end)
    local nextPage = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextPage:SetPoint("TOPLEFT", 228, -427); nextPage:SetSize(96, 22); nextPage:SetText("Proxima >")
    nextPage:SetScript("OnClick", function() self.trackerPage = math.min(self.trackerPages or 1, (self.trackerPage or 1)+1); self:RenderTracker() end)
    self.trackerPrevious, self.trackerNext = previous, nextPage
    self.trackerPageText = label(f, "GameFontHighlightSmall", 125, -433, 95)
    if f.EnableMouseWheel then
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", function(_, delta)
            self.trackerPage = math.max(1, math.min(self.trackerPages or 1, (self.trackerPage or 1) + (delta > 0 and -1 or 1)))
            self:RenderTracker()
        end)
    end
    self:SetTrackerLocked(self.db.options.trackerLocked)
    f:SetShown(self.db.options.trackerVisible == true)
    self:RenderTracker()
end

function A:RenderTracker()
    if not self.trackerFrame or not self.trackerFrame:IsShown() then return end
    -- UnitGUID may not exist yet at ADDON_LOADED. Restore once the character
    -- becomes available, and again when the player identity actually changes.
    local guid = type(UnitGUID) == "function" and UnitGUID("player")
    if guid and guid ~= self.trackerCharacter then self:RestoreTrackerPosition() end
    self:ApplyTrackerScale()
    local entries = self.Tracker:Snapshot(self.context)
    self.trackerPages = math.max(1, math.ceil(#entries / ROWS))
    self.trackerPage = math.max(1, math.min(self.trackerPages, self.trackerPage or 1))
    self.trackerPageText:SetText(string.format("%d / %d", self.trackerPage, self.trackerPages))
    self.trackerPrevious:SetEnabled(self.trackerPage > 1)
    self.trackerNext:SetEnabled(self.trackerPage < self.trackerPages)
    local ready = 0
    for _, entry in ipairs(entries) do if entry.quest.complete then ready = ready + 1 end end
    self.trackerSummary:SetText(string.format("%d no diario  |  %d para entregar", #entries, ready))
    for index, row in ipairs(self.trackerRows) do
        local entry = entries[(self.trackerPage-1)*ROWS+index]; row.entry = entry; row:SetShown(entry ~= nil)
        if entry then
            row.title:SetText((entry.focused and "> " or "") .. (entry.favorite and "* " or "") .. entry.quest.title)
            row.progress:SetText((entry.quest.complete and "|cff67df9b" or "|cff78c9ff") .. entry.progress.text .. "|r")
            if row.bar then row.bar:SetValue(entry.progress.percent); row.bar:SetShown(entry.progress.known or entry.progress.complete) end
            local lines = {}
            for i=1,math.min(3, #entry.quest.objectives) do
                local objective = entry.quest.objectives[i]
                lines[#lines+1] = (objective.finished and "|cff67df9b[OK] " or "|cffe8e4dc[ ] ") .. objective.text .. "|r"
            end
            if #lines == 0 then lines[1] = entry.quest.complete and "Procure quem recebe esta quest." or "O cliente nao informou objetivos." end
            row.objectives:SetText(table.concat(lines, "\n"))
        end
    end
    self.trackerFooter:SetText(#entries == 0 and "Aceite uma quest para acompanhar seus objetivos."
        or (#entries > ROWS and ("+" .. (#entries-ROWS) .. " no diario completo.  |  Shift+clique: favorito")
            or "Clique: destino  |  Botao direito: detalhes"))
end
