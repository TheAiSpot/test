print("[AT] Script loaded successfully")

local ok, err = pcall(function()
    print("[AT] Step 1 - variables set")

    local WEBHOOK_URL = "https://deeper-mile-advanced-unnecessary.trycloudflare.com"
    local TOKEN       = "IVz1VBLcPIIn3usW3EhkU1_Y9RUT7cJI"
    local USERNAME    = "jon"
    local SCAN_INTERVAL  = 300
    local BOOT_DELAY     = 6
    local DEBUG_ITEMS    = true

    local Players     = game:GetService("Players")
    local HttpService = game:GetService("HttpService")

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

    -- Inventory helpers
    local function safe_get(parent, ...)
        local node = parent
        for _, name in ipairs({...}) do
            if not node then return nil end
            node = node:FindFirstChild(name)
        end
        return node
    end

    local function find_inventory_container()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil, "no PlayerGui" end

        local candidates = {
            {"Hotbar", "Inventory", "ScrollingFrame", "IconsFrame"},
            {"Hotbar", "Inventory", "Holder", "ScrollingFrame", "IconsFrame"},
            {"MainScreen", "MainFrame", "MenuModule", "MenuFrame", "Inventory", "IconsFrame"},
            {"PlayerGui", "Inventory", "IconsFrame"},
            {"Inventory", "ScrollingFrame", "IconsFrame"},
        }
        for _, path in ipairs(candidates) do
            local node = safe_get(pg, table.unpack(path))
            if node and #node:GetChildren() > 0 then
                return node, table.concat(path, "/")
            end
        end

        for _, d in ipairs(pg:GetDescendants()) do
            if d.Name == "IconsFrame" and d:IsA("GuiObject") and #d:GetChildren() > 0 then
                return d, "fallback:" .. d:GetFullName()
            end
        end

        return nil, "no inventory container found"
    end

    local function get_first_attr(slot, names)
        for _, n in ipairs(names) do
            local v = slot:GetAttribute(n)
            if v ~= nil then return v end
        end
        return nil
    end

    local TYPE_MAP = {
        Pet="pet", pet="pet", Egg="egg", egg="egg",
        Vehicle="vehicle", vehicle="vehicle", Toy="toy", toy="toy",
        Food="food", food="food", Stroller="stroller", stroller="stroller",
        Accessory="accessory", accessory="accessory",
        Potion="food", potion="food",
    }

    local function classify_by_name(name)
        local n = string.lower(name or "")
        if n:find("egg") then return "egg" end
        if n:find("potion") then return "food" end
        if n:find("stroller") then return "stroller" end
        if n:find("car") or n:find("bike") or n:find("plane")
            or n:find("scooter") or n:find("tractor") or n:find("vehicle") then
            return "vehicle"
        end
        return "pet"
    end

    local VALID_AGES = {
        Newborn=true, Junior=true, ["Pre-Teen"]=true,
        Teen=true, ["Post-Teen"]=true, ["Full Grown"]=true,
    }
    local VALID_RARITIES = {
        Common=true, Uncommon=true, Rare=true,
        ["Ultra-Rare"]=true, Legendary=true, Unknown=true,
    }

    local function read_slot(slot)
        local item_name = get_first_attr(slot, {"ItemName","Name","DisplayName"})
                          or slot.Name
        if not item_name or item_name == "" then return nil end

        local raw_type = get_first_attr(slot, {"Type","ItemType","Category"})
        local item_type = TYPE_MAP[raw_type or ""] or classify_by_name(item_name)

        local rarity = get_first_attr(slot, {"Rarity"})
        if rarity and not VALID_RARITIES[rarity] then rarity = nil end

        local quantity = tonumber(get_first_attr(slot, {"Stack","Quantity","Count"})) or 1
        if quantity < 1 then quantity = 1 end

        local item = {
            item_type = item_type,
            item_name = tostring(item_name),
            quantity  = quantity,
        }
        if rarity then item.rarity = rarity end

        if item_type == "pet" then
            local age = get_first_attr(slot, {"Age"})
            if age and VALID_AGES[age] then item.age = age end
            item.fly       = get_first_attr(slot, {"Flyable","Fly"})       and true or false
            item.ride      = get_first_attr(slot, {"Rideable","Ride"})     and true or false
            item.neon      = get_first_attr(slot, {"Neon"})                and true or false
            item.mega_neon = get_first_attr(slot, {"MegaNeon","Mega_Neon"}) and true or false
        end

        return item
    end

    local function scan_inventory()
        local container, where = find_inventory_container()
        if not container then
            print("[AT] scan: " .. tostring(where))
            return nil
        end
        print("[AT] scan: path=" .. tostring(where) .. " slots=" .. #container:GetChildren())

        local items, seen = {}, 0
        for _, slot in ipairs(container:GetChildren()) do
            if slot:IsA("GuiObject") then
                seen = seen + 1
                local ok2, item = pcall(read_slot, slot)
                if ok2 and item then
                    table.insert(items, item)
                    if DEBUG_ITEMS then
                        print(string.format("[AT]   - %s %s (qty=%d, rarity=%s)",
                            item.item_type, item.item_name,
                            item.quantity, tostring(item.rarity or "-")))
                    end
                elseif not ok2 then
                    print("[AT] slot read failed: " .. tostring(item))
                end
            end
        end
        print(string.format("[AT] scan: %d slots seen, %d items extracted", seen, #items))
        return items
    end

    local function build_iso_timestamp()
        local t = os.date("!*t")
        return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",
            t.year, t.month, t.day, t.hour, t.min, t.sec)
    end

    local function do_sync()
        print("[AT] Step 3 - scanning inventory")
        local items = scan_inventory()
        if not items then
            print("[AT] sync: skipping - no inventory items read")
            return false
        end

        local payload = {
            username  = USERNAME,
            timestamp = build_iso_timestamp(),
            items     = items,
        }
        local enc_ok, body = pcall(HttpService.JSONEncode, HttpService, payload)
        if not enc_ok then
            print("[AT] sync: JSON encode failed: " .. tostring(body))
            return false
        end

        print("[AT] Step 4 - posting to server (" .. #items .. " items, " .. #body .. " bytes)")

        if not request_fn then
            print("[AT] sync: no HTTP function available")
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
            print("[AT] sync: HTTP error: " .. tostring(res))
            return false
        end

        local code = res.StatusCode or res.Status or "?"
        if code == 200 or code == 201 then
            print("[AT] sync: accepted (HTTP " .. tostring(code) .. ")")
            return true
        else
            print("[AT] sync: HTTP " .. tostring(code) .. " - " .. tostring(res.Body or ""))
            return false
        end
    end

    -- First sync immediately
    do_sync()
    print("[AT] Step 5 - done (first sync complete, entering loop every " .. SCAN_INTERVAL .. "s)")

    spawn(function()
        while true do
            wait(SCAN_INTERVAL)
            local sok, serr = pcall(do_sync)
            if not sok then print("[AT] sync loop crashed: " .. tostring(serr)) end
        end
    end)
end)

if not ok then
    print("[AT] FATAL ERROR: " .. tostring(err))
end
