local _, DebindPrivate = ...;
local Client = DebindPrivate.Client;

--- The first of `...` the client has an atlas for, and that atlas's info. We ship no art, so an
--- atlas the client lacks is a texture that draws nothing: camelot has no `common-icon-minus`
--- (69977), which retail draws the tri-state checkbox's middle mark with.
function Client.FirstAtlas(...)
    for i = 1, select("#", ...) do
        local name = select(i, ...);
        local info = C_Texture.GetAtlasInfo(name);
        if (info) then
            return name, info;
        end
    end
end
