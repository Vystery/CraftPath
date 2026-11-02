-- CraftPath :: Shop
-- Acting on the Shopping list:
--   Buy next          at the Auction House: opens Blizzard's buy page for the first item you still need with the
--                     quantity filled in (AuctionHouseFrame:SelectBrowseResult, then the commodities page's own
--                     SetQuantitySelected: the same calls CraftShuffle's planner uses, verified in game). You press
--                     Blizzard's Buy button yourself. Pressing again while that item is still needed skips to the next.
--   Buy vendor mats   at a merchant: buys what the list still needs that this merchant sells (BuyMerchantItem in
--                     the merchant's bundle sizes, at most a max stack per call, never more than your gold covers).

local _, CPa = ...
local Shop = {}
CPa.Shop = Shop

local function Name(itemID) return (CPa.UI and CPa.UI.ItemName and CPa.UI.ItemName(itemID)) or ("item " .. tostring(itemID)) end

function Shop:AtAuctionHouse() return AuctionHouseFrame and AuctionHouseFrame:IsShown() and true or false end
function Shop:AtMerchant() return MerchantFrame and MerchantFrame:IsShown() and true or false end

-- Rows of the current Shopping list still needed, in list order.
local function Needed(list, filter)
	local out = {}
	for _, e in ipairs(list or {}) do
		if e.itemID and (e.need or 0) > 0 and e.kind ~= "craft" and (not filter or filter(e)) then out[#out + 1] = e end
	end
	return out
end

---------------------------------------------------------------------------
-- Auction House
---------------------------------------------------------------------------

-- Commodities buy page quantity. The page has two parts that each keep a quantity: the buy box and the price list
-- (AuctionHouseCommoditiesBuyListMixin). The list starts at 1 and re-announces its own number on every refresh
-- (results loaded, more results fetched when the first listing is small), which reset a quantity set on the box
-- alone back to 1. So the quantity goes out the way typing it does: the Auction House frame's
-- CommoditiesQuantitySelectionChanged event, which both parts follow (Gethe wow-ui-source, live = forever branch,
-- Blizzard_AuctionHouseCommoditiesBuyFrame.lua / _CommoditiesList.lua). It is sent again when results arrive.
local function ApplyQuantity(itemID, qty)
	local ah = AuctionHouseFrame
	local frame = ah and ah.CommoditiesBuyFrame
	local display = frame and frame.BuyDisplay
	if not display then return false end
	if type(display.GetItemID) == "function" then
		local ok, current = pcall(display.GetItemID, display)
		if ok and current and current ~= itemID then return false end
	end
	local event = AuctionHouseFrameMixin and AuctionHouseFrameMixin.Event and AuctionHouseFrameMixin.Event.CommoditiesQuantitySelectionChanged
	if event and type(ah.TriggerEvent) == "function" then
		return (pcall(ah.TriggerEvent, ah, event, qty))
	end
	if type(display.SetQuantitySelected) == "function" then return (pcall(display.SetQuantitySelected, display, qty)) end
	return false
end

-- while a buy page CraftPath opened is loading its listings (10 s), every results event sets the quantity again
local applying
local function ReapplySoon()
	local a = applying
	if not a or (GetTime and GetTime() or 0) - a.t > 10 then return end
	if C_Timer and C_Timer.After then C_Timer.After(0, function() ApplyQuantity(a.itemID, a.qty) end) else ApplyQuantity(a.itemID, a.qty) end
end
for _, ev in ipairs({ "COMMODITY_SEARCH_RESULTS_RECEIVED", "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED" }) do
	CPa:RegisterEvent(ev, ReapplySoon)
end
CPa:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function() applying = nil end)
Shop.ApplyQuantity = ApplyQuantity

local function OpenBuyPage(itemID, qty)
	local ah = AuctionHouseFrame
	if not (ah and type(ah.SelectBrowseResult) == "function" and C_AuctionHouse and C_AuctionHouse.MakeItemKey) then return false end
	local CP = CPa.CP
	local minPrice = (CP and CP.Scanner and CP.Scanner.GetMin and CP.Scanner:GetMin(itemID))
		or (CP and CP.GetReagentCost and select(1, CP:GetReagentCost(itemID))) or 0
	local ok = pcall(function()
		local key = (CP and CP.Scanner and CP.Scanner.GetItemKey and CP.Scanner:GetItemKey(itemID)) or C_AuctionHouse.MakeItemKey(itemID)
		-- an open buy page only swaps its item key: go back to the list first so the new page searches
		local modes = AuctionHouseFrameDisplayMode
		if modes and ah.displayMode ~= nil and modes.Buy and type(ah.SetDisplayMode) == "function"
			and (ah.displayMode == modes.ItemBuy or ah.displayMode == modes.CommoditiesBuy) then
			ah:SetDisplayMode(modes.Buy)
		end
		ah:SelectBrowseResult({ itemKey = key, minPrice = minPrice, totalQuantity = qty })
	end)
	if not ok then
		-- fall back to the search bar
		local bar = ah.SearchBar
		if bar then
			ok = pcall(function()
				if bar.SearchBox and bar.SearchBox.SetText then bar.SearchBox:SetText(Name(itemID)) end
				if type(bar.StartSearch) == "function" then bar:StartSearch() end
			end)
		end
		return ok, false
	end
	applying = { itemID = itemID, qty = qty, t = GetTime and GetTime() or 0 }
	ApplyQuantity(itemID, qty)
	-- Blizzard marks the results as loaded in its own handler, maybe after ours: apply again shortly after
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function() ApplyQuantity(itemID, qty) end)
		C_Timer.After(0.4, function() ApplyQuantity(itemID, qty) end)
	end
	return true, true
end

-- The AH item to open next. Each item opens once per visit (bought items can come by mail, so the bags do not
-- show them yet: opening it again could buy it twice). Exception: the item opened last, partly bought into the
-- bags (a thin listing), opens again for the rest. Returns the row, its place and how many rows there are.
function Shop:NextAH(list)
	local rows = Needed(list, function(e) return e.kind ~= "vendor" end)
	self.opened = self.opened or {}
	for i, e in ipairs(rows) do
		if e.itemID == self.pending and self.pendingNeed and e.need < self.pendingNeed then return e, i, #rows end
	end
	for i, e in ipairs(rows) do
		if not self.opened[e.itemID] then return e, i, #rows end
	end
	return nil, 0, #rows
end

function Shop:BuyNext(list)
	if not self:AtAuctionHouse() then
		CPa:Print("open the Auction House first.")
		return
	end
	local e, i, n = self:NextAH(list)
	if not e then
		CPa:Print(n > 0 and "every item was opened once this visit; items you bought may still be in the mail. Reopen the Auction House to start over."
			or "nothing left to buy at the Auction House for this part of the route.")
		return
	end
	local ok, page = OpenBuyPage(e.itemID, e.need)
	if not ok then
		CPa:Print("could not open %s at the Auction House.", Name(e.itemID))
		return
	end
	self.opened[e.itemID] = true
	self.pending, self.pendingNeed = e.itemID, e.need
	CPa:Print(page and "%s (%d of %d): buy page opened for %d, press Buy to confirm." or "%s (%d of %d): searched, buy %d.",
		Name(e.itemID), i, n, e.need)
end

-- a new visit or another scope starts at the top of the list
function Shop:Reset() self.pending, self.pendingNeed, self.opened = nil, nil, {} end
CPa:RegisterEvent("AUCTION_HOUSE_CLOSED", function() Shop:Reset() end)

---------------------------------------------------------------------------
-- Merchant
---------------------------------------------------------------------------

local function MerchantItemID(index)
	if GetMerchantItemID then
		local ok, id = pcall(GetMerchantItemID, index)
		if ok and id then return id end
	end
	if GetMerchantItemLink then
		local ok, link = pcall(GetMerchantItemLink, index)
		local id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then return id end
	end
	return nil
end

-- itemID -> { index, unit, stack, available (items or nil = unlimited), maxStack }
function Shop:MerchantOffers()
	local offers = {}
	if not (GetMerchantNumItems and C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return offers end
	local ok, n = pcall(GetMerchantNumItems)
	for i = 1, (ok and n) or 0 do
		local id = MerchantItemID(i)
		local okI, info = pcall(C_MerchantFrame.GetItemInfo, i)
		if id and okI and type(info) == "table" and not info.hasExtendedCost and info.isPurchasable ~= false and (info.price or 0) > 0 then
			local stack = math.max(1, info.stackCount or 1)
			local maxStack = stack
			if GetMerchantItemMaxStack then
				local okM, m = pcall(GetMerchantItemMaxStack, i)
				if okM and type(m) == "number" and m > 0 then maxStack = m end
			end
			offers[id] = { index = i, unit = info.price / stack, stack = stack, maxStack = maxStack,
				available = (info.numAvailable and info.numAvailable >= 0) and info.numAvailable * stack or nil }
		end
	end
	return offers
end

-- What this merchant sells that the list still needs: { { e, offer, qty } }
function Shop:VendorList(list)
	local offers = self:MerchantOffers()
	local out = {}
	for _, e in ipairs(Needed(list)) do
		local o = offers[e.itemID]
		-- an AH row is bought here only when the merchant is not dearer
		if o and (e.kind == "vendor" or not e.unit or o.unit <= e.unit + 1e-9) then
			local qty = math.ceil(e.need / o.stack) * o.stack
			if o.available then qty = math.min(qty, o.available) end
			if qty > 0 then out[#out + 1] = { e = e, offer = o, qty = qty } end
		end
	end
	return out
end

function Shop:BuyVendor(list)
	if not self:AtMerchant() then
		CPa:Print("talk to a merchant first.")
		return
	end
	-- a second click before the bags update would buy the same things again
	local now = GetTime and GetTime() or 0
	if self.lastVendorBuy and now - self.lastVendorBuy < 2 then return end
	self.lastVendorBuy = now
	local todo = self:VendorList(list)
	if #todo == 0 then
		CPa:Print("this merchant sells nothing the list still needs.")
		return
	end
	local spent = 0
	local money0 = GetMoney and GetMoney() or math.huge -- does not drop until the server confirms: count it here
	for _, t in ipairs(todo) do
		local o, qty = t.offer, t.qty
		local money = money0 - spent
		if o.unit * qty > money then qty = math.floor(money / o.unit / o.stack) * o.stack end
		if qty <= 0 then
			CPa:Print("not enough gold for %s.", Name(t.e.itemID))
			break
		end
		local chunk = math.max(o.stack, math.floor(o.maxStack / o.stack) * o.stack)
		local left, bought = qty, 0
		while left > 0 do
			local n = math.min(left, chunk)
			local ok, err = pcall(BuyMerchantItem, o.index, n)
			if not ok then
				CPa:Print("buying %s failed: %s", Name(t.e.itemID), tostring(err))
				break
			end
			bought, left = bought + n, left - n
		end
		if bought > 0 then
			spent = spent + o.unit * bought
			CPa:Print("bought %d %s.", bought, Name(t.e.itemID))
		end
	end
	if spent > 0 then CPa:Print("spent %s at the merchant.", CPa:Money(spent)) end
end
