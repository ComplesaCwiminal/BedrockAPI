local modem = peripheral.find("modem")

local file = fs.open("sniffed.txt", "a")
local file2 = fs.open("sniffedUninterpreted.txt", "a")
local modems = {[1] = 65534, [2] = 0, [3] = 65535}
for i,v in ipairs(modems) do
    modem.open(v)
end
for i = 1, 100 do
    modem.open(i)
end

while true do
    local modemMessage = table.pack(os.pullEvent("modem_message"))

    local messageString = ""
    if type(modemMessage[5].message) == "table" then
        if modemMessage[5].message.mac ~= nil then
        for i,v in pairs(modemMessage[5].message) do
            print(modemMessage[3],":",i,v)
            local concatMsg = type(v) == "table" and "" or v
            if type(v) == "table" then
                for i2,v2 in ipairs(v) do
                    concatMsg = concatMsg .. string.char(v2)
                end
            end
            file2.writeLine(modemMessage[3] .. ": " .. i .. ": ".. tostring(concatMsg) .. "\n")

            if type(v) == "table" then
                file.write(i .. ": " .. tostring(v) .. ": ") -- Write the packets to a file
                local str = ""
                for i2, v2 in pairs(v) do
                    str = str .. string.format("%02x", v2)
                end
                file.write(str)
                file.write("\n") -- Write the packets to a file
            else
                local hex = {}
                for i=1,#v do
                    hex[#hex+1] = string.format("%02x", v:byte(i))
                end
                file.write(modemMessage[3] .. ": " .. i .. ": " .. table.concat(hex) .. "\n") -- Write the packets to a file
            end
        end
        else
            for i,v in pairs(modemMessage[5].message) do
                if type(v) == "table" then
                    if #v < 10 then
                        for i2,v2 in pairs(v) do
                            print(i,":",i2,v2)
                            file.write(i .. ": " .. i2 .. ": ".. tostring(v2) .. "\n")
                            file2.write(i .. ": " .. i2 .. ": ".. tostring(v2) .. "\n")
                        end
                    else 
                        local v2 = table.concat(v)
                        file2.write(i .. ": " .. tostring(v2) .. "\n")
                    end
                end
                print(modemMessage[3],":",i,v)
                file.write(modemMessage[3] .. ": " .. i .. ": ".. tostring(v) .. "\n")
                file2.write(modemMessage[3] .. ": " .. i .. ": ".. tostring(v) .. "\n")
            end
            file.writeLine("")
            file2.writeLine("")
        end
    end

end
