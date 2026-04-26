print("[AT] Script loaded successfully")

local ok, err = pcall(function()
    print("[AT] Step 1 - variables set")

    local WEBHOOK_URL        = (getgenv and getgenv().AT_URL)   or AT_URL   or "TRACKER_URL_HERE"
    local TOKEN              = (getgenv and getgenv().AT_TOKEN) or AT_TOKEN or "YOUR_TOKEN_HERE"
    local USERNAME           = game.Players.LocalPlayer.Name
    local SCAN_INTERVAL      = 300
    local HEARTBEAT_INTERVAL = 60
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

    print("[AT] Step 2 - waiting " .. BOOT_DELAY .. "s")
    wait(BOOT_DELAY)

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

        local v_count = add_category(inventory.vehicles,    "vehicle")
        local t_count = add_category(inventory.toys,        "toy")
        local s_count = add_category(inventory.strollers,   "stroller")
        local a_count = add_category(inventory.accessories, "accessory")
        local g_count = add_category(inventory.gifts,       "other")
        local f_count = add_category(inventory.food,        "food")
        print(string.format(
            "[AT] scan: vehicles=%d toys=%d strollers=%d accessories=%d gifts=%d food=%d",
            v_count, t_count, s_count, a_count, g_count, f_count))

        print(string.format("[AT] scan: total items = %d", #items))
        return items
    end

    local function build_iso_timestamp()
        local t = os.date("!*t")
        return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",
            t.year, t.month, t.day, t.hour, t.min, t.sec)
    end

    local function post_payload(payload, label)
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
            Url     = WEBHOOK_URL .. "/api/inventory",
            Method  = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["X-Token"]      = TOKEN,
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

    local function do_sync()
        print("[AT] Step 3 - scanning inventory")
        local items = scan_inventory()
        if not items then
            print("[AT] sync: skipping - no inventory items read")
            return false
        end

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
        post_payload(payload, "heartbeat")
    end

    -- First sync + first heartbeat immediately
    do_sync()
    send_heartbeat()
    print("[AT] Step 5 - done (entering loops: sync=" .. SCAN_INTERVAL ..
          "s, heartbeat=" .. HEARTBEAT_INTERVAL .. "s)")

    -- Inventory sync loop
    spawn(function()
        while true do
            wait(SCAN_INTERVAL)
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
