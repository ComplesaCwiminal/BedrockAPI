--[[+----------------------------------------------------------+
    |                     SOUND MODULE                         |
    |                    +------------+                        |
    | What this module handles: Sound, audio buffer/tracks,    | 
    | playback, exception handling, mixing, niceties           |
    |                                                          |
    |                      Description:                        |
    |  This module is designed to handle all raw audio data    |
    |  and details relating to it's dispatch. It's not perfect | 
    |   but it SHOULD be enough to not need to think to hard   | 
    |                       about it.                          |
    +----------------------------------------------------------+
---------------------------------------------------------------]]

local BedrockSound = {}

local state = {
    playback = "stopped"
}

local peripheralManager = {}

local speakerObjs = {}
local speakers = {}
-- Needed to track the write and playheads. The buffers are circular
local speakerMetas = {}

local function addSpeaker(order)
    local trueOrder = order <= #speakerMetas and order or #speakerMetas + 1
    trueOrder = trueOrder > 0 and trueOrder or 1

    local audioMetaBase = {pcm = {}, notes = {}}
    table.insert(speakers, order, {pcm = {}, notes = {}})
    table.insert(speakerMetas, order, audioMetaBase)
end
local function removeSpeaker(id)
    table.remove(speakers, id)
    table.remove(speakerMetas, id)
    table.remove(speakerObjs, id)
end

local trackBase = {}

local function getTrack(speakerID, tType, trackID)
    if speakers[speakerID] ~= nil and speakers[speakerID][tType] ~= nil and speakers[speakerID][tType][trackID] ~= nil then
        local trackObj = {
            trackID = trackID,
            position = speakers[speakerID][tType],
            metaData = speakerMetas[speakerID][tType][trackID],
            data = speakers[speakerID][tType][trackID],
        }
        setmetatable(trackObj, {__index = trackBase})

        return true, trackObj
    end
    return false, "Track does not exist"
end
--- Creates a track and inserts it. Contains no audio data by default
local function createTrack(speakerID, tType, order)

    table.insert(speakers[speakerID][tType], order, {})
    -- volume 1 is 100%
        -- If I learn fast fourier transforms I could also do piiiiitch~
    table.insert(speakerMetas[speakerID][tType], order, {playhead = 1, writehead = 1, volume = 1})


    local trueOrder = order <= #speakerMetas and order or #speakerMetas + 1
    trueOrder = trueOrder > 0 and trueOrder or 1

    return getTrack(speakerID, tType, trueOrder)
end

--- A quick helper for the road 
--- Only for use in prewriting
local function calculateFilled(readH, writeH)
    writeH = writeH + 1
    if writeH > BedrockSound.bufferSize then
        writeH = 1
    end
    return readH == writeH
end
local function pushByte(track, byte)
    if type(byte) == "number" then
        track.data[track.metaData.writehead] = byte
        track.metaData.writehead = track.metaData.writehead + 1

        -- Basic wraparound. Could be more concise, but fuck off.
        if track.metaData.writehead > BedrockSound.bufferSize then
            track.metaData.writehead = 1
        end
    else
        -- Notice how this doesn't say 8 bit?
            -- I'm going to hate myself
        error("Track data must be numerical PCM")
    end
end

-- How do tracks deal with wraparound data? Do they tell you before wraparound?
function trackBase:pushData(data, overwrite)
    -- If it's not a table treat it as if it were a byte
    if type(data) == "table" then
        -- Push the span of bytes or whatever else tbh. That's for our preprocessor to hate us for.
        for key, value in ipairs(data) do
            -- if after pushing they're equal. We can't add any more
            if calculateFilled(self.metaData.playhead, self.metaData.writehead) and not overwrite then
                return false, key, value -- Return false, and the key that failed to add.
            end

            pushByte(self, value)
        end
    else        -- if after pushing they're equal. We can't add any more
        if calculateFilled(self.metaData.playhead, self.metaData.writehead) and not overwrite then
            return false, nil, data -- Return false, and the key that failed to add.
        end
        
        pushByte(self, data)
    end
    
    return true
end


--- Get your current position in write track
function trackBase:getWritePos()
    return self.metaData.writehead
end

--- Get your current position in play track
function trackBase:getPlayPos()
    return self.metaData.playhead
end

function trackBase:seekBufferPlayhead(position)
end

function trackBase:seekBufferWritehead(position)
end

function trackBase:clearBuffer()
        self.position[self.trackID] = {}
        
        self.metaData.playhead = 1
        self.metaData.writehead = 1
end

local function Play()
    state.playback = "playing"
end

local function Pause()
    state.playback = "paused"
    for i,v in pairs(speakerObjs) do
        v.base.functions.stop()
    end
end

local function Stop()
    if state.playback ~= "stopped" then
        for i,v in pairs(speakerObjs) do
            v.base.functions.stop()
        end

        for i,types in ipairs(speakerMetas) do
            for i2,v2 in pairs(types) do
                for i3,v3 in pairs(v2) do
                    v3.playhead = 1
                end
            end
        end
    end

    state.playback = "stopped"
end

--- Inits a new speaker to be hotplug compatible
local function initSpeaker(id, speaker)
        addSpeaker(id)
        table.insert(speakerObjs, id, speaker)

        local curIter = id

        speaker.base.hooks.onDisconnect.addHook(function ()
            removeSpeaker(curIter)
        end)
end

--- This is the summer. After this you should normalize
local function mixTrackSample(speaker, tType, sample)
    if speakers[speaker] ~= nil and speakers[speaker][tType] ~= nil then
        local sum = 0
        for i,v in ipairs(speakers[speaker][tType]) do
            sum = sum + (v[sample] or 0)
        end
        -- They are uncorrelated generally so this is the best approach
        sum = sum / math.sqrt(#speakers[speaker][tType])
        return sum -- Make sure to clamp these before you actually use them. Not possible here because this is typically step one of many
    end
    return false, "Cannot find samples"
end

-- Initialize our hooks and set up hotplug stuff
local function init(modules, core)
    core:createHook(BedrockSound, "OnPlaybackError") -- We'll use this in playback errors. It'll pause if it errors.
    peripheralManager = modules.Input.peripheralManager

    for i,v in pairs(peripheralManager.connectedDevices) do
        print(i,v)
    end

    local iter = 1
    for i,v in pairs(peripheralManager.connectedDevices.speaker) do
        initSpeaker(iter, v)
        iter = iter + 1
    end
    modules.Input.hooks.onPeripheralConnect.addHook(function (device)
        if(device.base.type == "speaker") then
            initSpeaker(nil, device)
        end
    end)
end

local function main()
        while state.playback == "playing" do
            local threads = {}
            for i,v in ipairs(speakerObjs) do
                table.insert(threads, function ()
                local chunk = {}
                
                local samplePos = 0
                
                for i2 = 0, BedrockSound.bufferSize do
                    samplePos = speakerMetas[i]["pcm"].playhead + i2
                    samplePos = samplePos > BedrockSound.bufferSize and samplePos - BedrockSound.bufferSize or samplePos
                    
                    -- Implement downmixing later
                    chunk[i2] = math.min(math.max(mixTrackSample(i, "pcm", samplePos), -128), 127)
                end
                speakerMetas[i]["pcm"].playhead = speakerMetas[i]["pcm"].playhead + bufferSize
                speakerMetas[i]["pcm"].playhead = speakerMetas[i]["pcm"].playhead > BedrockSound.bufferSize and speakerMetas[i]["pcm"].playhead - BedrockSound.bufferSize or speakerMetas[i]["pcm"].playhead

                while not v.base.functions.playAudio(chunk) do
                    os.pullEvent("speaker_audio_empty")
                end
                end)
            end

            parallel.waitForAll(table.unpack(threads))
        end
end

local function cleanup()
    
end


BedrockSound = {
    type = "BedrockModule",
    moduleDefinition = {
        moduleName = "Sound",
        Init = init,
        Main = main,
        Cleanup = cleanup,
        events = {},
            dependencies = {
                requirements = {
                    {moduleName = "Core", version = "*"},
                    {moduleName = "Input", version = "*"}
                },
                optional = {

                },
                conflicts = {

                }
            },
    },
    bufferSize = 1024 * 32, -- A valid default.
    bitWidth = 8, -- Default is 8 to match output. It'll get downmixed if higher though.
    GetTrack = getTrack,
    CreateTrack = createTrack,
    Play = Play,
    Pause = Pause,
    Stop = Stop,
}

return BedrockSound