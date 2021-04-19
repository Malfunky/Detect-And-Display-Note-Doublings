
-- delayupdate = 0.7  
-- Future/Wanted features :  
 
--  + Exclude muted takes
--  + Delay chunkreading while zooming. 

-- USER DATA
minimumnotepixellength = 5 -- in pixels.  Notes snammer will not be tagged 
humanization_parameter = 0.1     
Fontsize = 15 
color = 0xFFFFFFF -- 0xRRGGBB
------------------------------


LICEFont = reaper.JS_LICE_CreateFont() 
reaper.JS_LICE_SetFontColor( LICEFont,   color)  
sectionID = 32060 -- midi editor 
local sb = reaper.SetToggleCommandState(sectionID ,({reaper.get_action_context()})[4],1)  
bitmaps = {}


function round(exact, quantum) --stackoverflow
  local quant,frac = math.modf(exact/quantum)
  return quantum * (quant + (frac > 0.5 and 1 or 0))
end

function go() 
    dcc=0
    count={} -- nasty global variable
    contemporary_table={} 
    noteoff={}
    for j = 0, reaper.CountMediaItems(0)-1 do 
       Item = reaper.GetMediaItem(0,j) 
       cnt = reaper.GetMediaItemNumTakes(Item)
       for k = 0, cnt -1  do 
         Take= reaper.GetTake(Item,k) 
         if reaper.TakeIsMIDI(Take) then 
              getTakeNotes(Take)
        end 
      end
   end 
end 
  
function ConvertCCTypeChunkToAPI(lane) --sader magic
    tLanes = {[ -1] = 0x200, -- Velocity
                  [128] = 0x201, -- Pitch
                  [129] = 0x202, -- Program select
                  [130] = 0x203, -- Channel pressure
                  [131] = 0x204, -- Bank/program
                  [132] = 0x205, -- Text
                  [133] = 0x206, -- Sysex
                  [167] = 0x207, -- Off velocity
                  [166] = 0x208, -- Notation
                  [ -2] = 0x210, -- Media Item lane
                 }    
    if type(lane) == "number" and 134 <= lane and lane <= 165 then 
      return (lane + 122) -- 14 bit CC range from 256-287 in API
    else 
      return (tLanes[lane] or lane) -- If 7bit CC, number remains the same
    end
end 
    
-- This function runs suprisinly fast. I doesnt blow up the system ,even on large midi takes.
function readfromchunk()   
    -- This is mostly taken from Julian Saders midiscripts 
    -- Gathers information like : 
    -- ME_LeftmostTick,  ME_HorzZoom , topvisiblepitch  , ME_PixelsPerPitch ,ME_midiviewHeight 
    -- activeChannel, ME_Docked, ME_TimeBase 
    tME_Lanes = {}  
    midiview  = reaper.JS_Window_FindChildByID(hwnd, 1001)
    item = reaper.GetMediaItemTake_Item(take) 
    _, chunk = reaper.GetItemStateChunk( item,"",1)  
    ----------------------------------------------------------------- 
    takeNum = reaper.GetMediaItemTakeInfo_Value(take, "IP_TAKENUMBER")
    takeChunkStartPos = 1
    for t = 1, takeNum do
      takeChunkStartPos = chunk:find("\nTAKE[^\n]-\nNAME", takeChunkStartPos+1)
      if not takeChunkStartPos then 
          reaper.MB("Could not find the active take's part of the item state chunk.", "ERROR", 0) 
          return false
      end
    end 
    takeChunkEndPos = chunk:find("\nTAKE[^\n]-\nNAME", takeChunkStartPos+1)
    activeTakeChunk = chunk:sub(takeChunkStartPos, takeChunkEndPos) 
    
    ME_LeftmostTick, ME_HorzZoom, ME_TopPitch, ME_PixelsPerPitch = 
    activeTakeChunk:match("\nCFGEDITVIEW (%S+) (%S+) (%S+) (%S+)") 
    ME_LeftmostTick,  ME_HorzZoom , ME_TopPitch , ME_PixelsPerPitch = 
    tonumber(ME_LeftmostTick),tonumber(ME_HorzZoom),tonumber(ME_TopPitch),tonumber(ME_PixelsPerPitch)
    activeChannel, ME_Docked, ME_TimeBase = activeTakeChunk:match("\nCFGEDIT %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+) %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+) %S+ (%S+)") 
    tbase= tonumber(ME_TimeBase) 
    topvisiblepitch = 127 - ME_TopPitch 

    laneID = -1 -- lane = -1 is the notes area
    tME_Lanes[-1] = {Type = -1, inlineHeight = 100} -- inlineHeight is not accurate, but will simply be used to indicate that this "lane" is large enough to be visible.
    for vellaneStr in activeTakeChunk:gmatch("\nVELLANE [^\n]+") do 
      laneType, ME_Height, inlineHeight = vellaneStr:match("VELLANE (%S+) (%d+) (%d+)")
      laneType, ME_Height, inlineHeight = ConvertCCTypeChunkToAPI(tonumber(laneType)), tonumber(ME_Height), tonumber(inlineHeight)
      if not (laneType and ME_Height and inlineHeight) then
          reaper.MB("Could not parse the VELLANE fields in the item state chunk.", "ERROR", 0)
          return(false)
      end    
      laneID = laneID + 1   
      tME_Lanes[laneID] = {VELLANE = vellaneStr, Type = laneType, ME_Height = ME_Height, inlineHeight = inlineHeight}
    end  
    
    if midiview then
      clientOK, rectLeft, rectTop, rectRight, rectBottom = reaper.JS_Window_GetClientRect(midiview) --takeChunk:match("CFGEDIT %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+) (%S+) (%S+) (%S+)") 
         if not clientOK then 
             reaper.MB("Could not determine the MIDI editor's client window pixel coordinates.", "ERROR", 0) 
             return(false) 
         end 
     ME_midiviewWidth  = ((rectRight-rectLeft) >= 0) and (rectRight-rectLeft) or (rectLeft-rectRight)--ME_midiviewRightPixel - ME_midiviewLeftPixel + 1
     ME_midiviewHeight = ((rectTop-rectBottom) >= 0) and (rectTop-rectBottom) or (rectBottom-rectTop)--ME_midiviewBottomPixel - ME_midiviewTopPixel + 1
     local laneBottomPixel = ME_midiviewHeight-1
     for i = #tME_Lanes, 0, -1 do
         tME_Lanes[i].ME_BottomPixel = laneBottomPixel
         tME_Lanes[i].ME_TopPixel    = laneBottomPixel - tME_Lanes[i].ME_Height + 10
         laneBottomPixel = laneBottomPixel - tME_Lanes[i].ME_Height
     end
     tME_Lanes[-1].ME_BottomPixel = laneBottomPixel
     tME_Lanes[-1].ME_TopPixel    = 62
     tME_Lanes[-1].ME_Height      = laneBottomPixel-61
     ME_BottomPitch = topvisiblepitch - math.floor(tME_Lanes[-1].ME_Height / ME_PixelsPerPitch) 
    end 
end 



function drawLICE(x,y,something) 
    dcc = dcc + 1  
    y = y + 62 
    bitmaps[dcc] = reaper.JS_LICE_CreateBitmap(true, 20 ,20 ) 
    reaper.JS_LICE_DrawText( bitmaps[dcc], LICEFont, something, 10,  0 , 0, 20, 20 )
    FontPos = ME_PixelsPerPitch/4  
    FontPos = math.floor(FontPos)
    did_it_work = reaper.JS_Composite(midiview  , x+2, y+FontPos, Fontsize , Fontsize ,  bitmaps[dcc], 0 , 0, 20 , 20 ,  false) 
end 

function UnlinkBitmap() 
   for j = 1 , #bitmaps do 
         reaper.JS_Composite_Unlink(midilink ,bitmaps[j],false) 
         reaper.JS_LICE_DestroyBitmap(bitmaps[j])
   end 
end

function getTakeNotes(take_) 
        -- get the visble aera in the active midieditor 
        -- compare all noteinfo with visble active notes 
        gotAllOK, MIDIstring = reaper.MIDI_GetAllEvts(take_, "") 
        MIDIlen = MIDIstring:len()  
        stringPos = 1  
        pos=0  
        qn_left = reaper.MIDI_GetProjQNFromPPQPos(take, ME_LeftmostTick)  
        contemporary_table={} -- must be cleared at each take
        while stringPos < MIDIlen do 
           offset, flags, ms, stringPos = string.unpack("i4Bs4", MIDIstring, stringPos) 
           pos=pos+offset 
           qn=reaper.MIDI_GetProjQNFromPPQPos(take_,pos)
           if qn> qn_left then 
             -- limit the rest to only visible notepositions
             midi =  ms:byte(1)>>4 
             if ms:len() == 3 and (midi == 9 or midi == 8) then 
               pitch = ms:byte(2)
               if pitch<=topvisiblepitch and pitch> ME_BottomPitch then 
                  --Finally lets go to town  
                  -- translate back to PPQpos akin to ACTIVE take
                  posA = reaper.MIDI_GetPPQPosFromProjQN(take,qn) -- be careful _-- this is the ACTIVE take 
                  
                  factor = posA - ME_LeftmostTick  -- works with tbase = not 1 and not 2
                  if tbase==1 or tbase==2 then 
                    timepos = reaper.MIDI_GetProjTimeFromPPQPos(take,  posA) -- posA is the position from the perspektive of the ACTIVE miditake
                    ME_LeftmostTime    = reaper.MIDI_GetProjTimeFromPPQPos(take, ME_LeftmostTick)
                    factor = timepos -  ME_LeftmostTime 
                    pixelpos_x = factor *ME_HorzZoom  
                  end
      
                  pixelpos_x = factor *ME_HorzZoom  
                  if pixelpos_x> ME_midiviewWidth then
                     goto stopit
                  end  
                  -- do the y pixelstuff 
                
                  factor = topvisiblepitch - pitch  
                  pixelpos_y = ME_PixelsPerPitch*factor 

                  pixelpos_x=math.floor(pixelpos_x) 
                  pixelpos_y=math.floor(pixelpos_y) 

                  _qn  = round(qn,humanization_parameter)
                  index0 = tostring(_qn).." "..tostring(pixelpos_y) 
                  
          
                 if midi==9 then  
                    contemporary_table[pixelpos_y] = {}
                    contemporary_table[pixelpos_y].idx = tostring(_qn)  
                    contemporary_table[pixelpos_y].x = pixelpos_x 
                    if count[index0] then 
                       --count[index0] = count[index0] + 1 
                       count[index0].count = count[index0].count + 1 
                       count[index0].x = pixelpos_x
                    else 
                      -- count[index0] =1 
                        count[index0]={}
                        count[index0].count =1 
                        count[index0].x = pixelpos_x
                    end 
                 end 
                
                 if midi==8 then  
                    if contemporary_table[pixelpos_y] then 
                       notelength = pixelpos_x - contemporary_table[pixelpos_y].x 
                       index0 = tostring(contemporary_table[pixelpos_y].idx ).." "..tostring(pixelpos_y) -- index corresponding to the noteon
                       noteoff[index0] = { notelength=notelength, take = take_} -- adding take into the table incase you want to discriminate between takes.
                    end
                 end           
               end 
             end 
           end 
        end 
        ::stopit::
end 

function draw() 
    for u,v in pairs(count) do 
      _, _,_y = u:match("(%d+).-(%d+).-(%d+)") -- Splits up the index string 
      if (noteoff[u] and noteoff[u].notelength>minimumnotepixellength) or not noteoff[u] then  -- This prevent tiny notes from being displayed when zoomed out
        if v.count>1 then  
          drawLICE(v.x,_y,v.count,LICEFont) 
        end
      end
   end 
end

function main() 
   hwnd = reaper.MIDIEditor_GetActive() 
   if hwnd then 
     take_=take 
     take = reaper.MIDIEditor_GetTake(hwnd) 
     if take~=take_ then update=true end 
     hash_ = hash or ""
     ret, hash = reaper.MIDI_GetHash(take,false,hash_)  
     if hash~=hash_ then update=true end 
   else 
     return reaper.defer(main) 
   end
   -- Detect changes in zoom/scroll info
   HORZ = {reaper.JS_Window_GetScrollInfo(midiview, "HORZ") } 
   VERT = {reaper.JS_Window_GetScrollInfo(midiview,"VERT")} 
   
   V_zoom_ = V_zoom or 0
   V_zoom = VERT[3] 
   V_scroll_ = V_scroll or 0
   V_scroll = VERT[2] 
   
   H_zoom_ = H_zoom or 0
   H_zoom = HORZ[3] 
   H_zoom2_ = H_zoom2 or 0
   H_zoom2 = HORZ[5]
   H_scroll_ = H_scroll or 0
   H_scroll = HORZ[2] 
 
   if V_zoom~=V_zoom_ or V_scroll~=V_scroll_ or H_zoom~=H_zoom_ or H_scroll~=H_scroll_ or H_zoom2~=H_zoom2_ then 
       UnlinkBitmap() 
       update =true 
   end 
  ------------------------------------------------------ 
  if update then 
      readfromchunk()   
      UnlinkBitmap() 
      go() 
      draw()
      update=false     
   end
   reaper.defer(main) 
end 

main()

reaper.atexit( function() 
  UnlinkBitmap() 
  reaper.JS_LICE_DestroyFont(LICEFont) 
  local sb = reaper.SetToggleCommandState(sectionID ,({reaper.get_action_context()})[4],0) 
end) 
