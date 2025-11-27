
local BedrockSound = {}
---@diagnostic disable: undefined-global, undefined-field
local audioBuffer = {
    
}

local tempo = 100
local bufferSize = 128


local trackBuilder = {}

function trackBuilder.new(Instrument, Volume, Pitch)
    local track = {}
    track.instance = {    
        position = 1,
        queuedNotes = 0,
        volume = Volume or 1, -- track master volume
        pitch = Pitch or 1, -- pitch shifter
        instrument = Instrument or "error",
        tracks = {}, -- child tracks, 
        notes = {}
    }
    
    track.instance._volume = Volume
    track.instance._pitch = Pitch


    local self = setmetatable(track, trackBuilder)
    self.__index = self
    
    function track:addNote(Pitch, Volume, Length)
        local addPos = #self.instance.notes + 1
        if addPos > bufferSize then
            addPos = 1
        end

        local note = {
            pitch = Pitch or 0,
            volume = Volume or 1,
            length = Length or (1/4), 
        }
        self.instance.notes[addPos] = note
        self.instance.queuedNotes = self.instance.queuedNotes + 1 
        return self
    end

    function track:addTrack(track)
        track.instance._volume = track.instance.volume + self.instance._volume
        track.instance._pitch = track.instance.pitch + self.instance._pitch
        table.insert(self.instance.tracks, track)
        return self
    end

    function track:addSpeaker(speaker)
        
    end

    function track:playNote(speaker)
        local track = self.instance
        if track.queuedNotes >= 1 then
            local note = track.notes[track.position]
            -- -1 is a rest note. Cope ong
            if note.pitch ~= -1 then
                local _trackVol = note.volume
                if track._volume ~= nil then
                    _trackVol = note.volume + track._volume
                else 
                    _trackVol = note.volume + track.volume
                end
                local _trackPitch = note.pitch
                if track._pitch ~= nil then
                    _trackVol = note.pitch + track._pitch
                else 
                    _trackVol = note.pitch + track._pitch
                end
                
                speaker.speaker.playNote(track.instrument, note.volume * track.volume, note.pitch * track.pitch)
                os.sleep((60/tempo) * note.length)
            end
            track.position = track.position + 1
            track.queuedNotes = self.instance.queuedNotes - 1
            if track.position > bufferSize then
                track.position = 1
            end 
        else 
            error("Audio buffer is empty!")
        end
        return self
    end

    function track:build()
        table.insert(audioBuffer, track)
        return track
    end

    return track
end

local function playNote(speaker)
    local noteFunc = {}
    for _,v in pairs(audioBuffer) do
        table.insert(noteFunc, function ()
            v:playNote(speaker)
        end)
    end

    parallel.waitForAll(table.unpack(noteFunc))
end

local function changeTempo(newTempo)
    tempo = newTempo
end

local function movePlayhead(newPos)
    for _,v in pairs(audioBuffer) do
        v.position = newPos
    end
end

-- ISTFG DO NOT RUN THIS FUNCTION WITHOUT IT USING PARALLEL, IT YIELDS FREQUENTLY, BUT IT'LL LOCK YOU UP FOR THE SONGS DURATION.
local function playBuffered(speaker)
    local trackThreads = {}
    for i,v in pairs(audioBuffer) do
            table.insert(trackThreads,function()
            while v.instance.queuedNotes >= 1 do
                v:playNote(speaker)
            end
        end)
    end
    parallel.waitForAll(table.unpack(trackThreads))
    return true
end

local function pauseBuffered()

end

local function stopBuffered()

end

local function init()
    
end

local function main()

end

local function cleanup()
    
end 

BedrockSound = {
    type = "BedrockModule",
    moduleAttributes = {
        name = "Sound",
        Init = init, -- 
        Main = main,
        Cleanup = cleanup,

        events = {
            
        }
    },
    AudioBuffer = audioBuffer,
    PlayBuffered = playBuffered,
    MovePlayhead = movePlayhead,
    PlayNote = playNote,
    
    TrackBuilder = trackBuilder,
}   

return BedrockSound