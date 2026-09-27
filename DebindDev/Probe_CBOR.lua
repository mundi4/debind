-- Probe_CBOR.lua
-- At login, round-trips hand-built tables through the client's CBOR, into `DebindDevDB.cbor`.
--
-- **What it is for.** `reshaping-stored-layers.md` §1-2 packs the payload with `C_EncodingUtil`
-- instead of LibSerialize, and the shape it packs leans on keys JSON would turn into strings: the
-- `[0]` spec slot, specs with a hole where a two-specialization class has no 3 and 4, number and
-- string keys side by side. Headless has no CBOR, so only a client can say which of these survive.
--
-- Each case goes through the whole string path (serialize, compress, base64, and back), and the
-- first difference is recorded by path with both types, since a key coming back as `"2"` instead
-- of `2` is exactly the failure being looked for.

local function Action(name)
    return { type = "spell", value = name, key = "SHIFT-1", seq = 1, conditions = { combat = true } };
end

local CASES = {
    { "spec 0..4", { [0] = { Action("a") }, [1] = { Action("b") }, [2] = { Action("c") },
        [3] = { Action("d") }, [4] = { Action("e") } } },
    { "spec 0,1,2,5", { [0] = { Action("a") }, [1] = { Action("b") }, [2] = { Action("c") },
        [5] = { Action("f") } } },
    { "spec 1,2,5", { [1] = { Action("b") }, [2] = { Action("c") }, [5] = { Action("f") } } },
    { "spec 0 only", { [0] = { Action("a") } } },
    { "spec 2 only", { [2] = { Action("c") } } },
    { "number and string key", { [1] = "number", ["1"] = "string" } },
    { "string key only", { ["1"] = { Action("a") } } },
    { "empty table", {} },
    { "empty table inside", { list = {}, spec = { [0] = {} } } },
    { "array with hole", { 1, nil, 3 } },
    { "class id keys", { specs = { [11] = 5, [8] = 2, [102] = 1 } } },
    { "negative and float keys", { [-1] = "neg", [1.5] = "float" } },
    { "values", { f = 1.5, big = 2 ^ 40, neg = -7, no = false, yes = true,
        nul = "a\0b", utf8 = "가나다", long = string.rep("x", 300) } },
    { "layers shape", {
        v = 3, dbver = 8,
        layers = {
            account = {
                GENERAL = { [0] = { Action("g") } },
                MAGE = { [0] = { Action("m0") }, [2] = { Action("m2") } },
                DRUID = { [1] = { Action("d1") }, [5] = { Action("d5") } },
            },
            ["Player-3041-0A1B2C3D"] = { MAGE = { [0] = { Action("c0") } } },
            [1] = { MAGE = { [2] = { Action("n2") } } },
            ["*"] = { ["*"] = { [4] = { Action("s4") } } },
        },
    } },
};

local function Describe(v)
    return format("%s(%s)", type(v), tostring(v));
end

--- The first place `got` differs from `want`, or nil. Keys are compared by value and type, so
--- a number key answered by a string key is reported as missing on one side and extra on the other.
local function FirstDiff(want, got, path)
    if (type(want) ~= type(got)) then
        return format("%s: want %s, got %s", path, Describe(want), Describe(got));
    end
    if (type(want) ~= "table") then
        if (want ~= got) then
            return format("%s: want %s, got %s", path, Describe(want), Describe(got));
        end
        return nil;
    end
    for k, v in pairs(want) do
        local diff = FirstDiff(v, rawget(got, k), path .. "[" .. Describe(k) .. "]");
        if (diff) then
            return diff;
        end
    end
    for k, v in pairs(got) do
        if (rawget(want, k) == nil) then
            return format("%s[%s]: extra, got %s", path, Describe(k), Describe(v));
        end
    end
    return nil;
end

local function RoundTrip(value)
    local util = C_EncodingUtil;
    local packed = util.EncodeBase64(util.CompressString(util.SerializeCBOR(value),
        Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize));
    local back = util.DeserializeCBOR(util.DecompressString(util.DecodeBase64(packed),
        Enum.CompressionMethod.Deflate));
    return back, #packed;
end

local function Sweep()
    local results = {};
    local passed = 0;
    for i = 1, #CASES do
        local name, value = CASES[i][1], CASES[i][2];
        local ok, back, size = pcall(RoundTrip, value);
        local result;
        if (not ok) then
            result = "raised: " .. tostring(back);
        else
            result = FirstDiff(value, back, "") or "ok";
            result = format("%s (%d chars)", result, size);
        end
        if (result:sub(1, 2) == "ok") then
            passed = passed + 1;
        end
        results[format("%02d %s", i, name)] = result;
    end
    return results, passed;
end

local probe = CreateFrame("Frame");
probe:RegisterEvent("PLAYER_LOGIN");
probe:SetScript("OnEvent", function()
    if (not C_EncodingUtil or not C_EncodingUtil.SerializeCBOR) then
        print("|cffff4444Debind|r cbor: this client has no C_EncodingUtil CBOR");
        return;
    end
    local ok, results, passed = pcall(Sweep);
    if (not ok) then
        print("|cffff4444Debind|r cbor raised: " .. tostring(results));
        return;
    end
    local version, build = GetBuildInfo();
    DebindDevDB = DebindDevDB or {};
    DebindDevDB.cbor = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = version .. "." .. build,
        results = results,
    };
    print(format("|cff33ff99Debind|r cbor: %d/%d cases round-trip (DebindDevDB.cbor)", passed, #CASES));
end);
