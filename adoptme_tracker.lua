print("[AT] Script loaded successfully")

local ok, err = pcall(function()
    print("[AT] Step 1 - variables set")

    local WEBHOOK_URL = "https://estates-partner-seal-strategic.trycloudflare.com"
    local TOKEN       = "IVz1VBLcPIIn3usW3EhkU1_Y9RUT7cJI"
    local USERNAME    = "jon"
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
            return clientData.get_data()[tostring(game.Players.LocalPlayer.UserId)]
        end)
        if not ok2 or not data then
            print("[AT] Player data not found: " .. tostring(data))
            return nil
        end
        return data
    end

    local VALID_AGES = {
        Newborn=true, Junior=true, ["Pre-Teen"]=true,
        Teen=true, ["Post-Teen"]=true, ["Full Grown"]=true,
    }

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

        -- Pets
        local pets = inventory.pets or {}
        local pet_count = 0
        for _, pet in pairs(pets) do
            local name  = pet.name or pet.petType or "Unknown Pet"
            local props = pet.properties or {}
            local item = {
                item_type = "pet",
                item_name = tostring(name),
                quantity  = 1,
                fly       = (props.flyable or pet.flyable) and true or false,
                ride      = (props.rideable or pet.rideable) and true or false,
                neon      = pet.neon and true or false,
                mega_neon = pet.megaNeon and true or false,
            }
            local age = pet.age or props.age
            if age and VALID_AGES[age] then item.age = age end
            table.insert(items, item)
            pet_count = pet_count + 1
            if DEBUG_ITEMS then
                print(string.format("[AT]   pet: %s (fly=%s ride=%s neon=%s mneon=%s)",
                    item.item_name,
                    tostring(item.fly), tostring(item.ride),
                    tostring(item.neon), tostring(item.mega_neon)))
            end
        end
        print(string.format("[AT] scan: pets found = %d", pet_count))

        -- Eggs: prefer inventory.eggs, fall back to egg-shaped entries in inventory.items
        local egg_count = 0
        local function add_egg(entry)
            local name = entry.name or entry.eggType or entry.itemType or "Unknown Egg"
            local item = {
                item_type = "egg",
                item_name = tostring(name),
                quantity  = tonumber(entry.count or entry.quantity or entry.stack) or 1,
            }
            table.insert(items, item)
            egg_count = egg_count + 1
            if DEBUG_ITEMS then
                print(string.format("[AT]   egg: %s (qty=%d)", item.item_name, item.quantity))
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
        print(string.format("[AT] scan: eggs found = %d", egg_count))

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
            username  = USERNAME,
            timestamp = build_iso_timestamp(),
            items     = items,
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
            username  = USERNAME,
            timestamp = build_iso_timestamp(),
            items     = {},
            heartbeat = true,
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
