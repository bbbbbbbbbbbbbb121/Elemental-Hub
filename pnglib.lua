---------------------------------------------------------------------------------------------
-- @ CloneTrooper1019, 2019
---------------------------------------------------------------------------------------------
-- [PNG Library]
--
--  A module for opening PNG files into a readable bitmap.
--  This implementation works with most PNG files.
--
---------------------------------------------------------------------------------------------

local sub, format, split, loadstring, spawn = string.sub, string.format, string.split, loadstring, task.spawn

local PNG = {}
PNG.__index = PNG

local chunks = {}
local modules = {}

-- Fetch the chunks:

function fetch(folder)
    local r = {}

    if isfolder("PNGLib/" .. folder) then
        for _, file in next, listfiles("PNGLib/" .. folder) do
            local ChunkName = sub(split(file, "/")[3], 1, #split(file, "/")[3] - 4)
            r[ChunkName] = loadstring(readfile(file))()
        end

        return r
    end

    for _, item in next, game:GetService("HttpService"):JSONDecode(
        request(
            {
                Url = "https://github.com/MaximumADHD/Roblox-PNG-Library/tree/master/" .. folder,
                Method = "GET",
                Headers = {
                    Accept = "application/json"
                }
            }
        ).Body
    ).payload.tree.items do
        local Content =
            game:HttpGet(
            format(
                "https://raw.githubusercontent.com/MaximumADHD/Roblox-PNG-Library/refs/heads/master/%s/%s",
                folder,
                item.name
            )
        )

        writefile("PNGLib/" .. folder .. "/" .. item.name, Content)

        r[sub(item.name, 1, #item.name - 4)] = loadstring(Content)()
    end

    return r
end

for n, v in next, fetch("Chunks") do
    chunks[n] = v
end

for n, v in next, fetch("Modules") do
    modules[n] = v
end

local Deflate = modules.Deflate
local Unfilter = (function()
    local Unfilter = {}

    function Unfilter:None(scanline, pixels, bpp, row)
        for i = 1, #scanline do
            pixels[row][i] = scanline[i]
        end
    end

    function Unfilter:Sub(scanline, pixels, bpp, row)
        for i = 1, bpp do
            pixels[row][i] = scanline[i]
        end

        for i = bpp + 1, #scanline do
            local x = scanline[i]
            local a = pixels[row][i - bpp]
            pixels[row][i] = bit32.band(x + a, 0xFF)
        end
    end

    function Unfilter:Up(scanline, pixels, bpp, row)
        if row > 1 then
            local upperRow = pixels[row - 1]

            for i = 1, #scanline do
                local x = scanline[i]
                local b = upperRow[i]
                pixels[row][i] = bit32.band(x + b, 0xFF)
            end
        else
            self:None(scanline, pixels, bpp, row)
        end
    end

    function Unfilter:Average(scanline, pixels, bpp, row)
        if row > 1 then
            for i = 1, bpp do
                local x = scanline[i]
                local b = pixels[row - 1][i]

                b = bit32.rshift(b, 1)
                pixels[row][i] = bit32.band(x + b, 0xFF)
            end

            for i = bpp + 1, #scanline do
                local x = scanline[i]
                local b = pixels[row - 1][i]

                local a = pixels[row][i - bpp]
                local ab = bit32.rshift(a + b, 1)

                pixels[row][i] = bit32.band(x + ab, 0xFF)
            end
        else
            for i = 1, bpp do
                pixels[row][i] = scanline[i]
            end

            for i = bpp + 1, #scanline do
                local x = scanline[i]
                local b = pixels[row - 1][i]

                b = bit32.rshift(b, 1)
                pixels[row][i] = bit32.band(x + b, 0xFF)
            end
        end
    end

    function Unfilter:Paeth(scanline, pixels, bpp, row)
        if row > 1 then
            local pr

            for i = 1, bpp do
                local x = scanline[i]
                local b = pixels[row - 1][i] or 0
                pixels[row][i] = bit32.band(x + b, 0xFF)
            end

            for i = bpp + 1, #scanline do
                local a = pixels[row][i - bpp]
                local b = pixels[row - 1][i] or 0
                local c = pixels[row - 1][i - bpp] or 0

                local x = scanline[i]
                local p = a + b - c

                local pa = math.abs(p - a)
                local pb = math.abs(p - b)
                local pc = math.abs(p - c)

                if pa <= pb and pa <= pc then
                    pr = a
                elseif pb <= pc then
                    pr = b
                else
                    pr = c
                end

                pixels[row][i] = bit32.band(x + pr, 0xFF)
            end
        else
            self:Sub(scanline, pixels, bpp, row)
        end
    end

    return Unfilter
end)()
local BinaryReader = modules.BinaryReader

local function getBytesPerPixel(colorType)
    if colorType == 0 or colorType == 3 then
        return 1
    elseif colorType == 4 then
        return 2
    elseif colorType == 2 then
        return 3
    elseif colorType == 6 then
        return 4
    else
        return 0
    end
end

local function clampInt(value, min, max)
    local num = tonumber(value) or 0
    num = math.floor(num + .5)

    return math.clamp(num, min, max)
end

local function indexBitmap(file, x, y)
    local width = file.Width
    local height = file.Height

    x = clampInt(x, 1, width)
    y = clampInt(y, 1, height)

    local bitmap = file.Bitmap
    local bpp = file.BytesPerPixel

    local i0 = ((x - 1) * bpp) + 1
    local i1 = i0 + bpp

    return bitmap[y], i0, i1
end

function PNG:GetPixel(x, y)
    local row, i0, i1 = indexBitmap(self, x, y)
    local colorType = self.ColorType

    local color, alpha
    do
        if colorType == 0 then
            local gray = unpack(row, i0, i1)
            color = Color3.fromHSV(0, 0, gray)
            alpha = 255
        elseif colorType == 2 then
            local r, g, b = unpack(row, i0, i1)
            color = Color3.fromRGB(r, g, b)
            alpha = 255
        elseif colorType == 3 then
            local palette = self.Palette
            local alphaData = self.AlphaData

            local index = unpack(row, i0, i1)
            index = index + 1

            if palette then
                color = palette[index]
            end

            if alphaData then
                alpha = alphaData[index]
            end
        elseif colorType == 4 then
            local gray, a = unpack(row, i0, i1)
            color = Color3.fromHSV(0, 0, gray)
            alpha = a
        elseif colorType == 6 then
            local r, g, b, a = unpack(row, i0, i1)
            color = Color3.fromRGB(r, g, b, a)
            alpha = a
        end
    end

    if not color then
        color = Color3.new()
    end

    if not alpha then
        alpha = 255
    end

    return color, alpha
end

function PNG.new(buffer)
    -- Create the reader.
    local reader = BinaryReader.new(buffer)

    -- Create the file object.
    local file = {
        Chunks = {},
        Metadata = {},
        Reading = true,
        ZlibStream = ""
    }

    -- Verify the file header.
    local header = reader:ReadString(8)

    if header ~= "\137PNG\r\n\26\n" then
        error("PNG - Input data is not a PNG file.", 2)
    end

    while file.Reading do
        local length = reader:ReadInt32()
        local chunkType = reader:ReadString(4)

        local data, crc

        if length > 0 then
            data = reader:ForkReader(length)
            crc = reader:ReadUInt32()
        end

        local chunk = {
            Length = length,
            Type = chunkType,
            Data = data,
            CRC = crc
        }

        local handler = chunks[chunkType]

        if handler then
            handler(file, chunk)
        end

        table.insert(file.Chunks, chunk)
    end

    -- Decompress the zlib stream.
    local success, response =
        pcall(
        function()
            local result = {}
            local index = 0

            Deflate:InflateZlib {
                Input = BinaryReader.new(file.ZlibStream),
                Output = function(byte)
                    index = index + 1
                    result[index] = string.char(byte)
                end
            }

            return table.concat(result)
        end
    )

    if not success then
        error("PNG - Unable to unpack PNG data. " .. tostring(response), 2)
    end

    -- Grab expected info from the file.

    local width = file.Width
    local height = file.Height

    local bitDepth = file.BitDepth
    local colorType = file.ColorType

    local buffer = BinaryReader.new(response)
    file.ZlibStream = nil

    local bitmap = {}
    file.Bitmap = bitmap

    local channels = getBytesPerPixel(colorType)
    file.NumChannels = channels

    local bpp = math.max(1, channels * (bitDepth / 8))
    file.BytesPerPixel = bpp

    -- Unfilter the buffer and
    -- load it into the bitmap.

    for row = 1, height do
        local filterType = buffer:ReadByte()
        local scanline = buffer:ReadBytes(width * bpp, true)

        bitmap[row] = {}

        if filterType == 0 then
            print("filterType 0")
            -- None
            Unfilter:None(scanline, bitmap, bpp, row)
        elseif filterType == 1 then
            print("filterType 1")
            -- Sub
            Unfilter:Sub(scanline, bitmap, bpp, row)
        elseif filterType == 2 then
            print("filterType 2")
            -- Up
            Unfilter:Up(scanline, bitmap, bpp, row)
        elseif filterType == 3 then
            print("filterType 3")
            -- Average
            Unfilter:Average(scanline, bitmap, bpp, row)
        elseif filterType == 4 then
            print("filterType 4")
            -- Paeth
            Unfilter:Paeth(scanline, bitmap, bpp, row)
        end
    end

    return setmetatable(file, PNG)
end

print(
    PNG.new(
        game:HttpGet(
            "https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/1.21.3/assets/minecraft/textures/block/barrel_side.png"
        )
    )
)
