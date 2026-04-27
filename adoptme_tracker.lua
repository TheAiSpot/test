print("[AT] Script loaded successfully")

local ok, err = pcall(function()
    print("[AT] Step 1 - variables set")

    local WEBHOOK_URL        = (getgenv and getgenv().AT_URL)        or AT_URL        or "TRACKER_URL_HERE"
    local TOKEN              = (getgenv and getgenv().AT_TOKEN)      or AT_TOKEN      or "YOUR_TOKEN_HERE"
    local MASTER_KEY         = (getgenv and getgenv().AT_MASTER_KEY) or AT_MASTER_KEY or ""
    local USERNAME           = game.Players.LocalPlayer.Name
    local SCAN_INTERVAL      = (getgenv and getgenv().AT_INTERVAL) or AT_INTERVAL or 300
    local HEARTBEAT_INTERVAL = 60
    local MIN_SYNC_GAP       = 60  -- minimum seconds between event-triggered syncs
    local BOOT_DELAY         = 6
    local DEBUG_ITEMS        = true

    local Players          = game:GetService("Players")
    local HttpService      = game:GetService("HttpService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local LocalPlayer = Players.LocalPlayer
    local tries = 0
    while not LocalPlayer and tries < 20 do
        wait(0.5)
        LocalPlayer = Players.LocalPlayer
        tries = tries + 1
    end
    if not LocalPlayer then
        print("[AT] ERROR: LocalPlayer never appeared")
        return
    end
    print("[AT] LocalPlayer = " .. tostring(LocalPlayer.Name))

    -- One-time dump of inventory keys so we can see what categories exist
    local function dump_inventory_keys()
        local ok, cd = pcall(function()
            return require(game.ReplicatedStorage
                :WaitForChild("ClientModules", 5)
                :WaitForChild("Core", 5)
                :WaitForChild("ClientData", 5))
        end)
        if not ok or not cd then
            print("[AT] dump: ClientData not available: " .. tostring(cd))
            return
        end
        local data = cd.get_data()[game.Players.LocalPlayer.Name]
        if not data or not data.inventory then
            print("[AT] dump: no inventory yet")
            return
        end
        print("[AT] === INVENTORY KEYS DUMP ===")
        for k, v in pairs(data.inventory) do
            local count = 0
            if type(v) == "table" then
                for _ in pairs(v) do count = count + 1 end
            end
            print("[AT]   " .. tostring(k) .. " = " ..
                  tostring(type(v)) .. " (" .. count .. " entries)")
        end
        print("[AT] === END INVENTORY KEYS ===")

        -- Top-level player-data dump — surfaces where bucks / event currency
        -- actually live so we can wire scans against the real key names.
        if DEBUG_ITEMS then
            print("[AT] === PLAYER DATA KEYS ===")
            for k, v in pairs(data) do
                print("[AT]   " .. tostring(k) .. " = " ..
                      tostring(type(v)))
            end
            print("[AT] === END PLAYER DATA KEYS ===")
        end
    end

    print("[AT] Step 2 - waiting " .. BOOT_DELAY .. "s")
    wait(BOOT_DELAY)
    dump_inventory_keys()

    -- HTTP function detection
    local request_fn = nil
    if request then request_fn = request
    elseif http_request then request_fn = http_request
    elseif syn and syn.request then request_fn = syn.request
    elseif fluxus and fluxus.request then request_fn = fluxus.request
    elseif http and http.request then request_fn = http.request
    end
    if not request_fn then
        print("[AT] WARNING: no HTTP request function found")
    else
        print("[AT] HTTP request function ready")
    end

    -- Open inventory UI to trigger Adopt Me's lazy data load
    local function open_inventory_ui()
        local ok3, _ = pcall(function()
            local hotbar = LocalPlayer.PlayerGui:FindFirstChild("Hotbar")
            if hotbar then
                local invBtn = hotbar:FindFirstChild("InventoryButton", true)
                if invBtn then invBtn:FireServer() end
            end
        end)
        wait(2)
    end

    -- Pull player state from Adopt Me's ClientData module
    local function get_inventory_via_clientdata()
        local ok1, clientData = pcall(function()
            return require(game.ReplicatedStorage:WaitForChild("ClientModules", 5)
                :WaitForChild("Core", 5)
                :WaitForChild("ClientData", 5))
        end)
        if not ok1 or not clientData then
            print("[AT] ClientData module not found: " .. tostring(clientData))
            return nil
        end

        local ok2, data = pcall(function()
            return clientData.get_data()[game.Players.LocalPlayer.Name]
        end)
        if not ok2 or not data then
            print("[AT] Player data not found: " .. tostring(data))
            return nil
        end
        return data
    end

    local AGE_MAP = {
        [1] = "Newborn",
        [2] = "Junior",
        [3] = "Pre-Teen",
        [4] = "Teen",
        [5] = "Post-Teen",
        [6] = "Full Grown",
    }

    local PREFIXES = {
        "basic_egg_2022_", "basic_egg_2021_", "basic_egg_2020_",
        "basic_egg_", "uncommon_", "rare_", "ultra_rare_",
        "legendary_", "common_", "event_",
    }

    local function strip_prefix(raw)
        local cleaned = raw or ""
        for _, prefix in ipairs(PREFIXES) do
            if cleaned:sub(1, #prefix) == prefix then
                return cleaned:sub(#prefix + 1)
            end
        end
        return cleaned
    end

    local function clean_pet_name(raw)
        if not raw then return "Unknown" end
        local cleaned = strip_prefix(raw)
        cleaned = cleaned:gsub("_", " ")
        cleaned = cleaned:gsub("(%a)([%w_']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end)
        return cleaned
    end

    local RARITY_MAP = {
        -- Common
        practice_dog="Common", dog="Common", cat="Common",
        chicken="Common", ground_sloth="Common", buffalo="Common",
        otter="Common", rabbit="Common", rat="Common",
        starter_egg="Common",
        -- Uncommon
        chocolate_labrador="Uncommon", fennec_fox="Uncommon",
        panda="Uncommon", reindeer="Uncommon", snow_puma="Uncommon",
        flamingo="Uncommon", bunny="Uncommon", pig="Uncommon",
        ox="Uncommon", red_panda="Uncommon",
        -- Rare
        bee="Rare", hedgehog="Rare", koala="Rare", monkey="Rare",
        polar_bear="Rare", sloth="Rare", turkey="Rare", cow="Rare",
        dodo="Rare", elephant="Rare", giraffe="Rare",
        kangaroo="Rare", llama="Rare", penguin="Rare",
        platypus="Rare", rhino="Rare", wolf="Rare",
        swordfish="Rare", horse="Rare", emu="Rare",
        -- Ultra-Rare
        crow="Ultra-Rare", dalmatian="Ultra-Rare",
        hyena="Ultra-Rare", meerkat="Ultra-Rare",
        porcupine="Ultra-Rare", sabertooth="Ultra-Rare",
        shiba_inu="Ultra-Rare", unicorn="Ultra-Rare",
        arctic_fox="Ultra-Rare", bat="Ultra-Rare",
        clownfish="Ultra-Rare", dragonfly="Ultra-Rare",
        zombie_buffalo="Ultra-Rare", albino_monkey="Ultra-Rare",
        -- Legendary
        dragon="Legendary", frost_dragon="Legendary",
        griffin="Legendary", parrot="Legendary",
        queen_bee="Legendary", shadow_dragon="Legendary",
        turtle="Legendary", kitsune="Legendary", owl="Legendary",
        phoenix="Legendary", robo_dog="Legendary",
        t_rex="Legendary", wyvern="Legendary",
        bat_dragon="Legendary", evil_unicorn="Legendary",
        frost_fury="Legendary", golden_unicorn="Legendary",
        diamond_unicorn="Legendary", skele_rex="Legendary",
        cerberus="Legendary", octopus="Legendary",
    }

    local function get_rarity(raw)
        if not raw then return nil end
        local key = strip_prefix(raw):lower()
        return RARITY_MAP[key]
    end

    local function scan_inventory()
        open_inventory_ui()

        local data = get_inventory_via_clientdata()
        if not data then
            print("[AT] scan: no ClientData available")
            return nil
        end

        local inventory = data.inventory
        if not inventory then
            print("[AT] scan: player data has no .inventory field")
            return nil
        end

        local items = {}

        -- Pets (and eggs that live in inventory.pets — Adopt Me ships eggs here too)
        local pets = inventory.pets or {}
        local pet_count = 0
        local egg_count_in_pets = 0
        local skipped_practice = 0
        local first = true
        for _, pet in pairs(pets) do
            local kind_early = pet.kind or pet.id or ""
            if kind_early == "practice_dog" or kind_early == "practice_pet" then
                -- Hidden starter pet that doesn't appear in the actual backpack.
                skipped_practice = skipped_practice + 1
            else
                if first then
                    print("[AT] DEBUG first pet fields:")
                    for k, v in pairs(pet) do
                        print("[AT]   " .. tostring(k) .. " = " .. tostring(v))
                        if type(v) == "table" then
                            for k2, v2 in pairs(v) do
                                print("[AT]     " .. tostring(k2) .. " = " .. tostring(v2))
                            end
                        end
                    end
                    first = false
                end

                local raw_name = pet.name or pet.petType or pet.displayName
                              or pet.kind or pet.id or "unknown"
                local item_name = clean_pet_name(raw_name)
                local props = pet.properties or {}
                local category = pet.category or ""
                local kind = pet.kind or pet.id or ""

                local item_type
                if category == "eggs" or kind:find("egg") then
                    item_type = "egg"
                else
                    item_type = "pet"
                end

                local item = {
                    item_type = item_type,
                    item_name = tostring(item_name),
                    quantity  = 1,
                }
                local rarity = get_rarity(raw_name)
                if rarity then item.rarity = rarity end

                if item_type == "pet" then
                    item.fly       = (props.flyable or props.fly) and true or false
                    item.ride      = (props.rideable or props.ride) and true or false
                    item.neon      = (pet.neon or props.neon) and true or false
                    item.mega_neon = (pet.megaNeon or props.megaNeon) and true or false
                    local age_num = tonumber(props.age)
                    if age_num and AGE_MAP[age_num] then
                        item.age = AGE_MAP[age_num]
                    end
                    pet_count = pet_count + 1
                else
                    egg_count_in_pets = egg_count_in_pets + 1
                end

                table.insert(items, item)
                if DEBUG_ITEMS then
                    if item_type == "pet" then
                        print(string.format("[AT]   pet: %s (rarity=%s fly=%s ride=%s neon=%s mneon=%s age=%s)",
                            item.item_name, tostring(item.rarity or "-"),
                            tostring(item.fly), tostring(item.ride),
                            tostring(item.neon), tostring(item.mega_neon), tostring(item.age)))
                    else
                        print(string.format("[AT]   egg(in pets): %s (rarity=%s)",
                            item.item_name, tostring(item.rarity or "-")))
                    end
                end
            end
        end
        print(string.format("[AT] scan: pets=%d eggs(in pets)=%d skipped(practice)=%d",
            pet_count, egg_count_in_pets, skipped_practice))

        -- Eggs: prefer inventory.eggs, fall back to egg-shaped entries in inventory.items
        local egg_count = 0
        local function add_egg(entry)
            local raw = entry.name or entry.eggType or entry.itemType or "unknown_egg"
            local item = {
                item_type = "egg",
                item_name = clean_pet_name(raw),
                quantity  = tonumber(entry.count or entry.quantity or entry.stack) or 1,
            }
            local rarity = get_rarity(raw)
            if rarity then item.rarity = rarity end
            table.insert(items, item)
            egg_count = egg_count + 1
            if DEBUG_ITEMS then
                print(string.format("[AT]   egg: %s (qty=%d rarity=%s)",
                    item.item_name, item.quantity, tostring(item.rarity or "-")))
            end
        end

        if inventory.eggs then
            for _, e in pairs(inventory.eggs) do add_egg(e) end
        end
        if inventory.items then
            for _, it in pairs(inventory.items) do
                local n = string.lower(tostring(it.name or it.itemType or ""))
                if n:find("egg") then add_egg(it) end
            end
        end
        print(string.format("[AT] scan: eggs (legacy paths) = %d", egg_count))

        -- Other inventory categories: vehicles, toys, strollers, accessories, gifts, food.
        -- Adopt Me ships these in their own tables under data.inventory.
        local function add_category(category_table, category_label)
            if not category_table then return 0 end
            local count = 0
            for _, entry in pairs(category_table) do
                local raw_name = entry.name or entry.kind or entry.id or "unknown"
                local item = {
                    item_type = category_label,
                    item_name = clean_pet_name(raw_name),
                    quantity  = tonumber(entry.count or entry.quantity or entry.stack) or 1,
                }
                local rarity = get_rarity(raw_name)
                if rarity then item.rarity = rarity end
                table.insert(items, item)
                count = count + 1
                if DEBUG_ITEMS then
                    print(string.format("[AT]   %s: %s (qty=%d rarity=%s)",
                        category_label, item.item_name, item.quantity,
                        tostring(item.rarity or "-")))
                end
            end
            return count
        end

        -- Vehicles: dedicated tables (every entry is a vehicle) plus mixed
        -- tables like inventory.items / inventory.backpack where we have to
        -- pick out vehicles by category flag or name hint. Adopt Me has
        -- shipped vehicles in items[] alongside other gear at various points,
        -- so we cannot rely on the dedicated tables alone.
        local VEHICLE_TABLES_DEDICATED = {
            "vehicles", "vehicle", "ride_items", "rideable",
        }
        local VEHICLE_TABLES_MIXED = { "items", "backpack" }
        local VEHICLE_NAME_HINTS = {
            "car", "bike", "plane", "scooter", "tractor", "helicopter",
            "jet", "boat", "ship", "train", "truck", "moped", "kart",
            "motorcycle", "snowmobile", "broom", "hoverboard", "carpet",
            "pram", "wagon", "balloon", "submarine", "skateboard",
            "skidoo", "rocket", "ufo", "vehicle", "scuba", "sleigh",
            "raft", "canoe",
        }

        local function looks_like_vehicle(entry, raw_name)
            local cat = string.lower(tostring(
                entry.category or entry.type or entry.itemType
                    or entry.item_type or ""))
            if cat == "vehicle" or cat == "vehicles"
               or cat == "ride" or cat == "rideable" then
                return true
            end
            if entry.is_vehicle == true or entry.isVehicle == true
               or entry.rideable == true then
                return true
            end
            local n = string.lower(tostring(raw_name or ""))
            if n == "" then return false end
            for _, hint in ipairs(VEHICLE_NAME_HINTS) do
                if n:find(hint, 1, true) then return true end
            end
            return false
        end

        local v_count = 0
        local function add_vehicle(entry)
            local raw_name = entry.name or entry.kind or entry.id or "unknown"
            local item = {
                item_type = "vehicle",
                item_name = clean_pet_name(raw_name),
                quantity  = tonumber(
                    entry.count or entry.quantity or entry.stack) or 1,
            }
            local rarity = get_rarity(raw_name)
            if rarity then item.rarity = rarity end
            table.insert(items, item)
            v_count = v_count + 1
            if DEBUG_ITEMS then
                print(string.format("[AT]   vehicle: %s (qty=%d rarity=%s)",
                    item.item_name, item.quantity,
                    tostring(item.rarity or "-")))
            end
        end

        for _, key in ipairs(VEHICLE_TABLES_DEDICATED) do
            local tbl = inventory[key]
            if type(tbl) == "table" then
                for _, entry in pairs(tbl) do add_vehicle(entry) end
            end
        end
        -- Mixed tables: only entries that classify as a vehicle. Do NOT
        -- skip just because we already saw the name in a dedicated table —
        -- stack_items() at the end merges duplicates by (type, name).
        for _, key in ipairs(VEHICLE_TABLES_MIXED) do
            local tbl = inventory[key]
            if type(tbl) == "table" then
                for _, entry in pairs(tbl) do
                    local raw_name = entry.name or entry.kind or entry.id or ""
                    if looks_like_vehicle(entry, raw_name) then
                        add_vehicle(entry)
                    end
                end
            end
        end

        local t_count = add_category(inventory.toys,        "toy")
        local s_count = add_category(inventory.strollers,   "stroller")
        local a_count = add_category(inventory.accessories, "accessory")
        local g_count = add_category(inventory.gifts,       "other")
        local f_count = add_category(inventory.food,        "food")
        print(string.format(
            "[AT] scan: vehicles=%d toys=%d strollers=%d accessories=%d gifts=%d food=%d",
            v_count, t_count, s_count, a_count, g_count, f_count))

        -- Potions: filter inventory tables for entries whose name contains
        -- "potion". Adopt Me sometimes ships them in `food`/`foods`, sometimes
        -- in `items`, sometimes in their own `potions` table.
        --
        -- Same potion name can appear once per stack slot in the inventory
        -- table — sum quantities across all slots so 9 stack slots become
        -- one entry with quantity=9 (not 1).
        local POTION_TABLES = { "potions", "foods", "food", "items", "consumables" }
        local potion_count = 0
        local potion_by_name = {}  -- cleaned_name -> item table
        local first_potion_logged = false
        local function read_qty(entry)
            -- Adopt Me uses different field names depending on the inventory
            -- table — try every observed name before defaulting to 1.
            local q = entry.count
                  or entry.amount
                  or entry.quantity
                  or entry.stack
                  or entry.stackSize
                  or entry.stackCount
            return tonumber(q) or 1
        end
        for _, key in ipairs(POTION_TABLES) do
            local tbl = inventory[key]
            if type(tbl) == "table" then
                for _, entry in pairs(tbl) do
                    local raw = entry.name or entry.kind or entry.id or ""
                    local lower = string.lower(tostring(raw))
                    if lower:find("potion") then
                        if not first_potion_logged then
                            print("[AT] DEBUG first potion raw:")
                            for dk, dv in pairs(entry) do
                                print("[AT]   " .. tostring(dk) .. "=" .. tostring(dv))
                            end
                            first_potion_logged = true
                        end
                        local cleaned = clean_pet_name(raw)
                        local qty = read_qty(entry)
                        local existing = potion_by_name[cleaned]
                        if existing then
                            existing.quantity = (existing.quantity or 0) + qty
                            if DEBUG_ITEMS then
                                print(string.format(
                                    "[AT]   potion+: %s (+%d, total=%d)",
                                    cleaned, qty, existing.quantity))
                            end
                        else
                            local item = {
                                item_type = "potion",
                                item_name = cleaned,
                                quantity  = qty,
                            }
                            local rarity = get_rarity(raw)
                            if rarity then item.rarity = rarity end
                            table.insert(items, item)
                            potion_by_name[cleaned] = item
                            potion_count = potion_count + 1
                            if DEBUG_ITEMS then
                                print(string.format("[AT]   potion: %s (qty=%d rarity=%s)",
                                    item.item_name, item.quantity, tostring(item.rarity or "-")))
                            end
                        end
                    end
                end
            end
        end

        -- Event currency: scan known currency names (event-driven, varies).
        local CURRENCY_NAMES = {
            candy=true, candies=true, stars=true, shells=true, tokens=true,
            tickets=true, gingerbread=true, fragments=true, hearts=true,
            snowflakes=true, pumpkins=true, treats=true, gems=true, coins=true,
            eggs_currency=true,
        }
        local currency_count = 0
        local function maybe_currency(raw)
            if not raw or raw == "" then return nil end
            local key = strip_prefix(tostring(raw)):lower():gsub("_", " ")
            for word in key:gmatch("%S+") do
                if CURRENCY_NAMES[word] then return true end
            end
            return CURRENCY_NAMES[key] == true
        end
        local CURRENCY_TABLES = {
            "currency", "currencies", "events", "event_items", "items",
            "eventCurrency", "event_currency", "seasonal", "limited",
        }
        for _, key in ipairs(CURRENCY_TABLES) do
            local tbl = inventory[key]
            if type(tbl) == "table" then
                for _, entry in pairs(tbl) do
                    local raw = entry.name or entry.kind or entry.id or ""
                    if maybe_currency(raw) then
                        local item = {
                            item_type = "event_currency",
                            item_name = clean_pet_name(raw),
                            quantity  = read_qty(entry),
                        }
                        table.insert(items, item)
                        currency_count = currency_count + 1
                        if DEBUG_ITEMS then
                            print(string.format("[AT]   event_currency: %s (qty=%d)",
                                item.item_name, item.quantity))
                        end
                    end
                end
            end
        end

        -- Top-level event currency: Adopt Me sometimes parks the current
        -- season's currency directly on the player blob (e.g. data.candy = 47).
        local EVENT_KEYS = {
            "candy", "candies", "stars", "tokens", "tickets",
            "shells", "hearts", "gems", "snowflakes", "pumpkins",
            "gingerbread", "treats", "fragments", "eventCurrency",
            "event_currency", "seasonal_currency", "limited_currency",
        }
        for _, key in ipairs(EVENT_KEYS) do
            local val = data[key]
            if type(val) == "number" and val > 0 then
                table.insert(items, {
                    item_type = "event_currency",
                    item_name = clean_pet_name(key),
                    quantity  = math.floor(val),
                })
                currency_count = currency_count + 1
                print("[AT] event currency at data." .. key
                      .. " = " .. tostring(val))
            end
        end

        -- Bucks: try common locations in ClientData first, then leaderstats.
        local bucks_value = nil
        local bucks_paths = {
            function() return data.bucks end,
            function() return data.currency and data.currency.bucks end,
            function() return data.player and data.player.bucks end,
            function() return data.economy and data.economy.bucks end,
            function() return data.money end,
            function() return data.coins end,
            function()
                local stats = game.Players.LocalPlayer:FindFirstChild("leaderstats")
                if stats then
                    local b = stats:FindFirstChild("Bucks") or stats:FindFirstChild("bucks")
                    if b and b.Value then return b.Value end
                end
                return nil
            end,
            function()
                local stats = game.Players.LocalPlayer:FindFirstChild("leaderstats")
                if stats then
                    local m = stats:FindFirstChild("Money") or stats:FindFirstChild("money")
                    if m and m.Value then return m.Value end
                end
                return nil
            end,
        }
        for _, fn in ipairs(bucks_paths) do
            local ok_b, v = pcall(fn)
            if ok_b and type(v) == "number" then
                bucks_value = v
                break
            end
        end
        -- Fuzzy fallback: scan top-level numeric keys whose name suggests
        -- currency. Catches future renames like data.player_bucks etc.
        if not bucks_value and type(data) == "table" then
            for k, v in pairs(data) do
                local key_lower = string.lower(tostring(k))
                if type(v) == "number" and
                   (key_lower:find("buck")
                    or key_lower:find("money")
                    or key_lower:find("coin")) then
                    bucks_value = v
                    print("[AT] bucks found at key: " .. tostring(k)
                          .. " = " .. tostring(v))
                    break
                end
            end
        end
        if bucks_value then
            table.insert(items, {
                item_type = "bucks",
                item_name = "Bucks",
                quantity  = math.floor(bucks_value),
            })
        end

        print(string.format("[AT] scan: potions=%d event_currency=%d bucks=%s",
            potion_count, currency_count,
            bucks_value and tostring(math.floor(bucks_value)) or "?"))

        print(string.format("[AT] scan: total items = %d", #items))
        return items
    end

    local function build_iso_timestamp()
        local t = os.date("!*t")
        return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",
            t.year, t.month, t.day, t.hour, t.min, t.sec)
    end

    local function post_payload(payload, label, path)
        if not request_fn then
            print("[AT] " .. label .. ": no HTTP function available")
            return false
        end
        local enc_ok, body = pcall(HttpService.JSONEncode, HttpService, payload)
        if not enc_ok then
            print("[AT] " .. label .. ": JSON encode failed: " .. tostring(body))
            return false
        end
        local req_ok, res = pcall(request_fn, {
            Url     = WEBHOOK_URL .. (path or "/api/inventory"),
            Method  = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["X-Token"]      = (MASTER_KEY == "" and TOKEN or nil),
                ["X-Master-Key"] = (MASTER_KEY ~= "" and MASTER_KEY or nil),
            },
            Body    = body,
        })
        if not req_ok then
            print("[AT] " .. label .. ": HTTP error: " .. tostring(res))
            return false
        end
        local code = res.StatusCode or res.Status or "?"
        if code == 200 or code == 201 then
            return true
        end
        print("[AT] " .. label .. ": HTTP " .. tostring(code) .. " - " .. tostring(res.Body or ""))
        return false
    end

    -- Merge duplicate items by (item_type, item_name) so the server
    -- sees one row per unique item with summed quantity
    local function stack_items(raw_items)
        local stacked = {}
        local seen = {}
        for _, item in ipairs(raw_items) do
            local key = tostring(item.item_type) .. "|" .. tostring(item.item_name)
            if seen[key] then
                seen[key].quantity = (seen[key].quantity or 1) + (item.quantity or 1)
            else
                local copy = {}
                for k, v in pairs(item) do copy[k] = v end
                seen[key] = copy
                table.insert(stacked, copy)
            end
        end
        return stacked
    end

    local function do_sync()
        print("[AT] Step 3 - scanning inventory")
        local items = scan_inventory()
        if not items then
            print("[AT] sync: skipping - no inventory items read")
            return false
        end
        items = stack_items(items)
        print(string.format("[AT] scan: stacked items = %d", #items))

        local payload = {
            username        = USERNAME,
            roblox_username = game.Players.LocalPlayer.Name,
            timestamp       = build_iso_timestamp(),
            items           = items,
        }
        print("[AT] Step 4 - posting to server (" .. #items .. " items)")
        if post_payload(payload, "sync") then
            print("[AT] sync: accepted")
            return true
        end
        return false
    end

    local function send_heartbeat()
        local payload = {
            username        = USERNAME,
            roblox_username = game.Players.LocalPlayer.Name,
            timestamp       = build_iso_timestamp(),
            items           = {},
            heartbeat       = true,
        }
        post_payload(payload, "heartbeat", "/api/heartbeat")
    end

    -- First sync + first heartbeat immediately
    do_sync()
    send_heartbeat()
    print("[AT] Step 5 - done (entering loops: sync=" .. SCAN_INTERVAL ..
          "s, heartbeat=" .. HEARTBEAT_INTERVAL .. "s)")

    -- Debounced trigger so rapid changes don't spam the server
    local last_sync_time = 0
    local function maybe_sync()
        local now = os.time()
        if now - last_sync_time >= MIN_SYNC_GAP then
            last_sync_time = now
            print("[AT] triggered by inventory change")
            local sok, serr = pcall(do_sync)
            if not sok then print("[AT] event sync crashed: " .. tostring(serr)) end
        end
    end

    -- Watch Adopt Me's ClientData for inventory changes (event-driven sync)
    local function watch_inventory_changes(on_change)
        local ok_w, err_w = pcall(function()
            local cd = require(game.ReplicatedStorage
                :WaitForChild("ClientModules", 5)
                :WaitForChild("Core", 5)
                :WaitForChild("ClientData", 5))
            cd.DataChanged:Connect(function(player, key)
                if player == game.Players.LocalPlayer.Name then
                    print("[AT] inventory changed: " .. tostring(key))
                    if key == "inventory" or key == "pets"
                       or key == "items" or key == "trades" then
                        on_change()
                    end
                end
            end)
        end)
        if not ok_w then
            print("[AT] DataChanged watch not available - timer only: " .. tostring(err_w))
        else
            print("[AT] DataChanged watch active (min gap=" .. MIN_SYNC_GAP .. "s)")
        end
    end

    watch_inventory_changes(maybe_sync)

    -- Inventory sync loop (fallback if event watch fails or misses changes)
    spawn(function()
        while true do
            wait(SCAN_INTERVAL)
            last_sync_time = os.time()
            local sok, serr = pcall(do_sync)
            if not sok then print("[AT] sync loop crashed: " .. tostring(serr)) end
        end
    end)

    -- Heartbeat loop (online status)
    spawn(function()
        while true do
            wait(HEARTBEAT_INTERVAL)
            local hok, herr = pcall(send_heartbeat)
            if not hok then print("[AT] heartbeat loop crashed: " .. tostring(herr)) end
        end
    end)
end)

if not ok then
    print("[AT] FATAL ERROR: " .. tostring(err))
end
