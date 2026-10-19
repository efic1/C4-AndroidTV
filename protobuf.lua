WireType_VarInt			= 0
WireType_Fixed64		= 1
WireType_String			= 2
WireType_OpenGroup	= 3
WireType_CloseGroup	= 4
WireType_Fixed32 		= 5


function GetWireMessageFingerPrint(WireMessage)
	local FP = ""
	for k, v in pairs(WireMessage) do
		if (type(k) == "number") then
			FP = FP .. "[F" .. k .. "]"
		elseif (type(k) == "string" and k == "WireType") then
				FP = FP .. "[WT" .. v .. "]"
		end
		
		if (type(v) == "table") then
			FP = FP .. GetWireMessageFingerPrint(v)
		end
	end
	return FP
end


function EncodeVarInt(Value)
	local VarIntBytes = ""
	
	if(Value < 0) then
		Value = Value + bit.lshift(1, 64) -- UNTESTED
	end
	
	while(bit.rshift(Value, 7) > 0) do
		VarIntBytes = VarIntBytes .. string.char(bit.bor(bit.band(Value, 127), 128)) -- 7 Bits of Integer with MSB 1
		Value = bit.rshift(Value, 7)
	end
	VarIntBytes = VarIntBytes .. string.char(bit.band(Value, 127))
	
	return VarIntBytes;
end

function EncodeTag(ID, WireType)
	return EncodeVarInt(bit.bor(bit.lshift(ID, 3), bit.band(WireType, 7)))
end

-- Every message on the remote (6466) and pairing (6467) ports is prefixed with its length as a
-- protobuf varint. A single raw byte is only correct below 128 bytes (and string.char() raises
-- an error above 255), so always encode it as a varint.
function FrameMessage(Payload)
	return EncodeVarInt(#Payload) .. Payload
end

-- Reads the varint length prefix at the start of Buffer.
-- Returns Length, HeaderBytes; nil when the prefix is not complete yet; false when it is invalid.
function ReadLengthPrefix(Buffer)
	local Length = 0
	for i = 1, math.min(#Buffer, 4) do
		local b = Buffer:byte(i)
		Length = Length + bit.lshift(bit.band(b, 127), (i - 1) * 7)
		if (b < 128) then return Length, i end
	end
	if (#Buffer >= 4) then return false end -- 4 continuation bytes = 2^28+ bytes, not a real message
	return nil
end

function EncodeWire(WireMessage, Level)
	local Data = ""
	for k, v in pairs(WireMessage) do
		if (type(k) == "number") then
			--Data = Data .. "\n" ..  "[" .. k .. "] = "
		
			if (type(v) == "number") then
				Debug("@@@@@AAAAA@@@@@")
				--toprint = toprint .. v .. ", "
			elseif (type(v) == "string") then
				Debug("@@@@@BBBBB@@@@@")
				--toprint = toprint .. "\"" .. v .. "\", "
			elseif (type(v) == "table") then
					if(v.WireType ~= nil) then --Encode Wire Type
						--Debug("V:" .. v.ID .. "\tWireType: " .. v.WireType .. "\tValue: " .. v.Value)
						if(v.WireType == WireType_VarInt) then
							Data = Data .. EncodeTag(v.ID, v.WireType) .. EncodeVarInt(v.Value)
						elseif(v.WireType == WireType_String) then
							Data = Data .. EncodeTag(v.ID, v.WireType) .. EncodeVarInt(#v.Value) .. v.Value
						else
							Debug("UNSUPPORTED WIRETYPE!")
						end
					else
						--Debug("Generic SubObject:" .. k)
						local SubData = EncodeWire(v)
						Data = Data .. EncodeTag(k, WireType_String) .. EncodeVarInt(#SubData) .. SubData
					end
				--toprint = toprint .. PrintWireMessage(v, indent) .. " "
			else
				Debug("@@@@@CCCCC@@@@@")
				--toprint = toprint .. "\"" .. tostring(v) .. "\", "
			end
		
		
	elseif (type(k) == "string") then
			--local WireType = v["WireType"]
			--Debug("WT:" .. WireType)
			Debug("@@@@@DDDDD@@@@@")
			--toprint = toprint  .. k ..  " = "   
			if(k == "WireType") then
				HasWireType = true
			end
		end
	end

	return Data
end

function DecodeVarInt(Data, StartPosition)
	if(StartPosition > #Data) then Debug("DecodeVarInt RETURN NULL") return end
	local VarIntR = {}
	
	VarIntR.Value = 0
	VarIntR.Bytes = 1
		
	local CurPosition = StartPosition;
	while(bit.band(Data:byte(CurPosition), 128) == 128) do --128 = 1000 000
		local SubNumber = bit.band(Data:byte(CurPosition), 127)
		VarIntR.Value = bit.bor(VarIntR.Value, bit.lshift(SubNumber, (CurPosition - StartPosition) * 7)) -- 127 = 0111 1111
		CurPosition = CurPosition + 1;
		VarIntR.Bytes = VarIntR.Bytes + 1;
	end
	VarIntR.Value = bit.bor(VarIntR.Value, bit.lshift(Data:byte(CurPosition), (CurPosition - StartPosition) * 7)) -- 127 = 0111 1111
	
	VarIntR.FieldID = bit.rshift(VarIntR.Value, 3)
	
	return VarIntR;
end



-- DecodeWire guesses whether a string field is a nested message and tries to decode it; that guess
-- fails on ordinary strings (app names, ...) and is not an error. Only report problems at the top
-- level, where they mean a message really could not be decoded.
function DecodeNote(Text, Level)
	if ((Level or 1) <= 1) then
		DebugLevel(Text, Level or 1)
	end
end

function DecodeWire(Data, Level)
	local CurrentPosition = 1
	local BytesRemaining = 0
	
	local LoopNum = 1
	local Message = {}
	
	while(#Data - CurrentPosition > 0) do	
		--DebugLevel("Processing Loop " .. LoopNum .. "	Bytes Remaining: " .. (#Data - CurrentPosition), Level)
		--DebugLevel("Processing Payload: " .. GetHexString(Data:sub(CurrentPosition, CurrentPosition + 50)) .. "...", Level)
		LoopNum = LoopNum + 1
		
		local Tag = DecodeVarInt(Data, CurrentPosition)
		local WireType = bit.band(Tag.Value, 7) -- 7 = 0000 0111
		
		Message[Tag.FieldID] = {}
		Message[Tag.FieldID].ID = Tag.FieldID
		Message[Tag.FieldID].WireType = WireType
		
		CurrentPosition = CurrentPosition + Tag.Bytes
		
		if(WireType == WireType_VarInt) then				--VarInt				1-10 Bytes									int32, int64, uint32, bool etc.
			local VarInt = DecodeVarInt(Data, CurrentPosition)
			Message[Tag.FieldID].Value = VarInt.Value
			CurrentPosition = CurrentPosition + VarInt.Bytes
			BytesRemaining = #Data - CurrentPosition  --DebugLevel("Bytes Remaining=" .. BytesRemaining, Level)
			
		elseif(WireType == WireType_Fixed64) then 		--Fixed64				8 Bytes (Little Endian)			fixed64, sfixed64, double
			DecodeNote("UNSUPPORTED FIXED64 WIRE TYPE", Level)
			--CurrentPosition = CurrentPosition + 8
		elseif(WireType == WireType_String) then 		--IdeLim				var len + (len * bytes)			string, bytes, (inner) messages
			local StringLength = DecodeVarInt(Data, CurrentPosition)
			
			CurrentPosition = CurrentPosition + StringLength.Bytes
			BytesRemaining = #Data - CurrentPosition  --DebugLevel("#Bytes Remaining=" .. BytesRemaining, Level)
			
			--[[ INTERPRET AS STRING ]]--
			Message[Tag.FieldID].TagBytes = StringLength.Value
			Message[Tag.FieldID].Value = Data:sub(CurrentPosition, CurrentPosition+StringLength.Value -1)
				
				--[[ INTERPRET AS SUB OBJECT ]]--
			if(BytesRemaining == (StringLength.Value - 1)) then
				local SubWireBegin = CurrentPosition - StringLength.Bytes
				local SubWire = DecodeWire(Data:sub(CurrentPosition, CurrentPosition + StringLength.Value - 1), Level+1)
				
				if(#SubWire > 0 or table.map_length(SubWire) > 0) then
					Message[Tag.FieldID] = SubWire
				else
					--print("Test")
				end
			elseif(BytesRemaining == (StringLength.Value + 1)) then
				local SubWireBegin = CurrentPosition - StringLength.Bytes
				local SubWire = DecodeWire(Data:sub(CurrentPosition, CurrentPosition + StringLength.Value + 1), Level+1)
				
				if (#SubWire > 0 or table.map_length(SubWire) > 0) then
					Message[Tag.FieldID] = SubWire
				else
					--print("Test")
				end
			end
			CurrentPosition = CurrentPosition + StringLength.Value

		elseif(WireType == WireType_OpenGroup) then 		--StartGroup		N/A													N/A
			DecodeNote("UNSUPPORTED START_GROUP WIRE TYPE", Level)

		elseif(WireType == WireType_CloseGroup) then 		--EndGroup			N/A													N/A
			DecodeNote("UNSUPPORTED END_GROUP WIRE TYPE", Level)

		elseif(WireType == WireType_Fixed32) then 		--Fixed32				4 Bytes (Little Endian)			fixed32, sfixed32, float
			DecodeNote("UNSUPPORTED FIXED32 WIRE TYPE", Level)
			--CurrentPosition = CurrentPosition + 4
		else
			DecodeNote("UNKNOWN WIRE TYPE", Level)
			return {}
		end
	end
	return Message
end

function table.map_length(t)
    local c = 0
    for k,v in pairs(t) do
         c = c+1
    end
    return c
end
