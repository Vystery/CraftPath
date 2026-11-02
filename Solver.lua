-- CraftPath :: Solver
-- The cheapest way from one skill to another. Pure Lua (no game API), so the harness can test it offline.
--
-- Skill-up chance of one craft at skill s (fits the recorded crafts: Enchant Chest - Stamina gave 20 points in
-- 20 orange crafts, Minor Agility 9 points in 10 yellow crafts at 115-123 with gray at 155; Bolt of Linen Cloth
-- 12 points in 16 yellow crafts at 25-36 and 13 points in 70 green crafts at 37-49, the formula expects 16 and 80):
--   s < yellow         1
--   yellow <= s < gray (gray - s) / (gray - yellow)
--   s >= gray          0
-- Expected crafts for one point = 1 / chance, so the expected cost of a point is (cost per craft) / chance.
--
-- Route = shortest path over skill levels. An edge "recipe r from skill a to b" costs r's training price once
-- plus the expected crafts from a to b. Learned recipes have no training price, so their edges are one point
-- long and the solver can switch at every level; unlearned ones are tried for every length.

local _, CPa = ...
local Solver = {}
CPa.Solver = Solver

local INF = math.huge
local STEP_PENALTY = 0.01 -- copper per step: among equal routes, the one with fewer steps

---------------------------------------------------------------------------
-- Difficulty thresholds
---------------------------------------------------------------------------

-- Colour seen at a skill narrows where yellow, green and gray start.
local function Narrow(b, colour, from, to)
	if colour == 0 then
		b.yellow.lo = math.max(b.yellow.lo, to + 1)
	elseif colour == 1 then
		b.yellow.hi = math.min(b.yellow.hi, from)
		b.green.lo = math.max(b.green.lo, to + 1)
	elseif colour == 2 then
		b.green.hi = math.min(b.green.hi, from)
		b.gray.lo = math.max(b.gray.lo, to + 1)
	elseif colour == 3 then
		b.gray.hi = math.min(b.gray.hi, from)
	end
end

local function Clamp(v, range)
	if v < range.lo then return range.lo end
	if v > range.hi then return range.hi end
	return v
end

local function Pinned(range) return range.lo == range.hi end

-- in = { learnAt = n|nil, trivial = n|nil, seen = { { colour, from, to }, ... }, step = 20, span = 75 }
-- Returns { yellow, green, gray, yellowKnown, grayKnown, mismatch }.
--   gray: maxTrivialLevel when it agrees with the colours seen, else the colours, else a guess
--   yellow: seen exactly, else gray - 2 * step (the 20-point spacing), or halfway between learn skill and gray when
--   that spacing does not fit the colours seen; green: seen exactly, else halfway between yellow and gray
function Solver.Thresholds(input)
	local step = input.step or 20
	local b = {
		yellow = { lo = input.learnAt or 1, hi = INF },
		green = { lo = 1, hi = INF },
		gray = { lo = 1, hi = INF },
	}
	for _, o in ipairs(input.seen or {}) do Narrow(b, o[1], o[2], o[3]) end
	-- keep the order yellow <= green <= gray in the bounds
	b.green.lo = math.max(b.green.lo, b.yellow.lo)
	b.gray.lo = math.max(b.gray.lo, b.green.lo)

	local th = {}
	local gray, grayKnown, mismatch
	local trivial = input.trivial
	if trivial and trivial >= b.gray.lo and trivial <= b.gray.hi then
		gray, grayKnown = trivial, true
	else
		mismatch = trivial ~= nil or nil
		if Pinned(b.gray) then
			gray, grayKnown = b.gray.lo, true
		elseif Pinned(b.yellow) then
			gray = b.yellow.lo + 2 * step
		elseif Pinned(b.green) then
			gray = math.floor(b.green.lo + step + 0.5)
		else
			gray = (input.learnAt or b.yellow.lo) + (input.span or 75)
		end
		gray = Clamp(gray, b.gray)
	end
	local yellow
	if Pinned(b.yellow) then
		yellow = b.yellow.lo
	else
		local guess = math.floor(gray - 2 * step + 0.5)
		if guess < b.yellow.lo then
			-- the 20-point spacing does not fit (low recipes, still orange past gray - 40): yellow halfway between the
			-- skill the recipe is learned at and gray (Bolt of Linen Cloth 1 / 25 / 50, Linen Bag 5 / 30 / 65). It stays
			-- put while you level, unlike "one above the last orange seen", which moved with every skill-up.
			guess = math.floor(((input.learnAt or b.yellow.lo) + gray) / 2)
		end
		yellow = Clamp(guess, b.yellow)
	end
	-- green halfway between yellow and gray: every recorded recipe has it (25 / 37 / 50, 30 / 47 / 65, 40 / 50 / 60,
	-- and the 20-point spacing of the Enchanting recording)
	local green = Pinned(b.green) and b.green.lo or Clamp(math.floor((yellow + gray) / 2), b.green)
	if yellow > gray then yellow = gray end
	if green < yellow then green = yellow end
	if green > gray then green = gray end
	th.yellow, th.green, th.gray = yellow, green, gray
	th.yellowKnown = Pinned(b.yellow)
	th.greenKnown = Pinned(b.green)
	th.grayKnown = grayKnown or false
	th.mismatch = mismatch
	return th
end

function Solver.Chance(th, skill)
	if skill < th.yellow then return 1 end
	if skill >= th.gray then return 0 end
	return (th.gray - skill) / (th.gray - th.yellow)
end

-- Expected points from one craft of r at a skill: its own chance plus, for intermediates you craft for it (3 Bolts
-- of Linen Cloth per Linen Bag), their crafts' chances: r.bonus = { { th, per = crafts of it per craft of r } }.
-- While the bolts are still orange a bag "bundle" gives up to 4 points.
-- ownOnly (parts-first order, how Craft next / Craft all work): the parts are crafted before the recipe, as their
-- own route step, so a craft of r gives only its own chance.
function Solver.Gain(r, skill, ownOnly)
	local g = Solver.Chance(r.th, skill)
	if ownOnly then return g end
	for _, b in ipairs(Solver.V(r, skill).bonus or {}) do g = g + b.per * Solver.Chance(b.th, skill) end
	return g
end

-- A recipe's price can change by skill band (a reagent becomes craftable): r.variants = { { from, cost, solveCost,
-- bonus, ... }, ... } sorted by from; the band for a skill, or r itself without bands.
function Solver.V(r, skill)
	local vs = r.variants
	if not vs then return r end
	local pick = vs[1]
	for _, v in ipairs(vs) do if skill >= v.from then pick = v end end
	return pick
end

-- Is a crafted reagent bought instead at this skill? Only with a buy price on the entry (buyDelta, "Craft reagents"
-- off) and only where its craft gives no point; a reagent made from a bought one is not crafted either.
function Solver.Bought(bo, skill)
	if bo.parent and Solver.Bought(bo.parent, skill) then return true end
	return bo.buyDelta ~= nil and Solver.Chance(bo.th, skill) <= 0
end

-- Extra copper per craft of r at a skill for the reagents bought instead of crafted there.
function Solver.Extra(r, skill)
	local extra = 0
	for _, bo in ipairs(Solver.V(r, skill).bonus or {}) do
		if bo.buyDelta and Solver.Bought(bo, skill) then extra = extra + bo.buyDelta end
	end
	return extra
end

-- 0 orange, 1 yellow, 2 green, 3 gray at a skill
function Solver.Colour(th, skill)
	if skill < th.yellow then return 0 end
	if skill < th.green then return 1 end
	if skill < th.gray then return 2 end
	return 3
end

---------------------------------------------------------------------------
-- Route
---------------------------------------------------------------------------

-- opts = { from, to, breaks = { [skill] = true } (rank caps: steps are not merged across them),
--          recipes = { { id, cost = per craft (copper, may be < 0), solveCost = what the route decides by
--          (cost floored at 0 plus a time cost per craft; defaults to cost), learnCost = 0 when learned,
--          learnAt = skill (nil when learned), th = Thresholds(...) }, ... } }
-- Returns { steps = { { recipe, from, to, crafts, cost, learnCost } }, total, crafts, reached, gap = skill | nil }
--   gap: the first skill no usable recipe gives a point at (the route stops there, reached = gap)
function Solver.Solve(opts)
	local from, to = opts.from, opts.to
	local recipes = {}
	for _, r in ipairs(opts.recipes or {}) do
		if type(r.cost) == "number" and r.th then recipes[#recipes + 1] = r end
	end
	local result = { steps = {}, total = 0, crafts = 0, from = from, to = to }
	if not (from and to) or to <= from then return result end

	-- per recipe and skill: expected crafts for the next point (nil = no point possible there)
	local crafts = {}
	for i, r in ipairs(recipes) do
		local row = {}
		for s = from, to - 1 do
			if not r.learnAt or s >= r.learnAt then
				local p = Solver.Gain(r, s, opts.partsFirst)
				if p > 0 and type(Solver.V(r, s).cost) == "number" then row[s] = 1 / p end
			end
		end
		crafts[i] = row
	end

	-- a level no recipe gives a point at ends the route there
	for s = from, to - 1 do
		local any = false
		for i = 1, #recipes do
			if crafts[i][s] then any = true break end
		end
		if not any then
			result.gap = s
			to = s
			break
		end
	end
	result.reached = to
	if to <= from then return result end

	local best, choice = {}, {}
	best[to] = 0
	for s = to - 1, from, -1 do
		best[s] = INF
		for i, r in ipairs(recipes) do
			local row = crafts[i]
			if row[s] then
				local fixed = (r.learnCost or 0) + STEP_PENALTY
				local acc = fixed
				local last = (fixed > STEP_PENALTY) and to or (s + 1)
				for e = s + 1, last do
					local n = row[e - 1]
					if not n then break end
					local v = Solver.V(r, e - 1)
					acc = acc + n * ((v.solveCost or v.cost) + Solver.Extra(r, e - 1))
					local rest = best[e]
					if rest < INF and acc + rest < best[s] then
						best[s] = acc + rest
						choice[s] = { i, e }
					end
				end
			end
		end
	end

	-- walk the choices point by point: neighbouring points of the same recipe form one step, except across a rank
	-- cap (breaks), so "Train: Journeyman" sits between 35-75 and 75-93. Each step also counts how many of its
	-- points the recipe gives itself and how many the intermediates crafted for it give (st.inter).
	local s = from
	while s < to do
		local i, e = choice[s][1], choice[s][2]
		local r = recipes[i]
		for x = s, e - 1 do
			local n = crafts[i][x]
			local v = Solver.V(r, x)
			local last = result.steps[#result.steps]
			local st
			if last and last.recipe == r and last.to == x and (last.variant or r) == v and not (opts.breaks and opts.breaks[x]) then
				st = last
				st.to = x + 1
				if x == s then st.learnCost = st.learnCost + (r.learnCost or 0) end -- another edge: its training too
			else
				st = { recipe = r, from = x, to = x + 1, crafts = 0, var = 0, cost = 0, own = 0, inter = {}, interBy = {},
					variant = r.variants and v or nil, learnCost = (x == s) and (r.learnCost or 0) or 0 }
				result.steps[#result.steps + 1] = st
			end
			st.crafts = st.crafts + n
			-- crafts until a point are geometric: variance (1-p)/p^2 = n^2 - n with n = 1/p
			st.var = st.var + math.max(0, n * n - n)
			st.cost = st.cost + n * (v.cost + Solver.Extra(r, x))
			st.own = st.own + n * Solver.Chance(r.th, x)
			for k, bo in ipairs(v.bonus or {}) do
				local key = bo.itemID or k
				local it = st.interBy[key]
				if not it then
					it = { recipe = bo.recipe, itemID = bo.itemID, crafts = 0, points = 0, bought = 0, top = bo.parent == nil }
					st.interBy[key] = it
					st.inter[#st.inter + 1] = it
				end
				if Solver.Bought(bo, x) then
					if bo.buyDelta then it.bought = it.bought + n * (bo.items or 0) end
				else
					it.crafts = it.crafts + n * bo.per
					if not opts.partsFirst then it.points = it.points + n * bo.per * Solver.Chance(bo.th, x) end
				end
			end
		end
		s = e
	end
	for _, st in ipairs(result.steps) do
		result.total = result.total + st.cost + st.learnCost
		result.crafts = result.crafts + st.crafts
	end
	return result
end

---------------------------------------------------------------------------
-- Route from the mats in your bags (no buying, no training)
---------------------------------------------------------------------------
-- Mats run out, so this is not a shortest path: point by point it takes the recipe that uses up the least AH
-- value of what you own for the next expected point, among those your remaining mats still cover.
-- Trainer recipes: point by point a training price always loses to one more craft, so the choice is made on the
-- whole route instead. Start with known recipes only; try adding each trainer recipe and keep the one that makes
-- the route best (further first, then less mat value + training); repeat until no addition helps. A kept recipe
-- counts from its learn skill and its training is paid where the route first uses it.
-- opts = { from, to, bags = { [itemID] = count },
--          recipes = { { id, th, learnAt = nil|skill, learnCost = 0|copper, reagents = { { itemID, qty, unit } } } } }
-- Returns the Solve shape plus used = { [itemID] = expected count used }, mats (AH value of the mats used) and
-- training (gold for recipes trained on the way); total = mats + training.
local function Greedy(opts, allowed)
	local from, to = opts.from, opts.to
	local left = {}
	for itemID, n in pairs(opts.bags or {}) do left[itemID] = n end
	local result = { steps = {}, total = 0, crafts = 0, from = from, to = to, used = {}, bagsOnly = true }
	if not (from and to) or to <= from then
		result.reached = from
		return result
	end
	local trained = {}
	local s = from
	while s < to do
		local best, bestValue, bestP, bestMats
		for _, r in ipairs(opts.recipes or {}) do
			local usable = not r.learnAt or (allowed[r] and s >= r.learnAt)
			local p = (r.th and usable) and Solver.Chance(r.th, s) or 0
			if p > 0 and #(r.reagents or {}) > 0 then
				local ok, value = true, 0
				for _, rg in ipairs(r.reagents) do
					local need = rg.qty / p
					if (left[rg.itemID] or 0) < need - 1e-9 then ok = false break end
					value = value + need * (rg.unit or 0)
				end
				if ok and (not best or value < bestValue - 1e-9 or (math.abs(value - bestValue) <= 1e-9 and p > bestP)) then
					best, bestValue, bestP, bestMats = r, value, p, value
				end
			end
		end
		if not best then
			result.gap = s
			break
		end
		for _, rg in ipairs(best.reagents) do
			local need = rg.qty / bestP
			left[rg.itemID] = left[rg.itemID] - need
			result.used[rg.itemID] = (result.used[rg.itemID] or 0) + need
		end
		local learnCost = 0
		if not trained[best] then
			trained[best] = true
			learnCost = best.learnCost or 0
		end
		local last = result.steps[#result.steps]
		if last and last.recipe == best then
			last.to, last.crafts, last.cost = s + 1, last.crafts + 1 / bestP, last.cost + bestMats
			last.var = (last.var or 0) + math.max(0, 1 / bestP / bestP - 1 / bestP)
		else
			result.steps[#result.steps + 1] = { recipe = best, from = s, to = s + 1, crafts = 1 / bestP,
				var = math.max(0, 1 / bestP / bestP - 1 / bestP), cost = bestMats,
				learnCost = learnCost }
		end
		s = s + 1
	end
	result.reached = s
	result.mats, result.training = 0, 0
	for _, st in ipairs(result.steps) do
		result.mats = result.mats + st.cost
		result.training = result.training + st.learnCost
		result.crafts = result.crafts + st.crafts
	end
	result.total = result.mats + result.training
	result.left = left
	return result
end

local function Better(a, b)
	if a.reached ~= b.reached then return a.reached > b.reached end
	return a.total < b.total - 1e-6
end

function Solver.SolveFromBags(opts)
	local allowed = {}
	local best = Greedy(opts, allowed)
	local candidates = {}
	for _, r in ipairs(opts.recipes or {}) do
		if r.learnAt and r.learnAt < (opts.to or 0) then candidates[#candidates + 1] = r end
	end
	while true do
		local pick, pickRes
		for _, r in ipairs(candidates) do
			if not allowed[r] then
				allowed[r] = true
				local res = Greedy(opts, allowed)
				allowed[r] = nil
				if Better(res, pickRes or best) then pick, pickRes = r, res end
			end
		end
		if not pick then break end
		allowed[pick] = true
		best = pickRes
	end
	return best
end

-- Usual range of a step's crafts (10% - 90%, normal approximation; never below one craft per point).
function Solver.Range(st)
	local sd = math.sqrt(math.max(st.var or 0, 0))
	local lo = math.max(st.to - st.from, st.crafts - 1.28 * sd)
	return math.floor(lo + 0.5), math.ceil(st.crafts + 1.28 * sd - 1e-9)
end
