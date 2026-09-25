--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
-- Semantic display inks only. Fixture RGB, swatches and MIDI LEDs are independent.
local M: any={names={"COCKPIT","GRAPHITE","PHOSPHOR","CLASSIC"},ink={},current=-1}
local classic={
    bright=0xFFFFFF,body=0xC8D0DC,dim=0x8890A0,faint=0x505868,
    rule=0x202632,track=0x202632,fill=0x30A0D0,warn=0xC08070,alert=0xFF3020,
    tab=0x101018,tab_active=0x2A3A55,tab_dim=0x707888,
    card=0x111B27,card_dim=0x91A4B8,card_body=0xD4DCE5,card_rule=0x344556,
    accent=0x67D4C0,selected=0x15352F,choice_dim=0x9AAABB,
    menu_accent=0xFFBE62,menu_bg=0x21190F,menu_dim=0x75634D,
    menu_selected=0x65451E,menu_card=0x302416,
    grid=0x202A36,grid_empty=0x0D1118,window=0x18212C,window_cell=0x101820,
}
local palettes={
    {bright=0xF3F3F1,body=0xD0D0CE,dim=0x959593,faint=0x676765,
     rule=0x292929,track=0x222222,fill=0xB8BCBA,tab=0x111111,tab_active=0x303030,tab_dim=0x8B8B89,
     card=0x141414,card_dim=0x969694,card_body=0xDDDDDA,card_rule=0x393939,
     accent=0x80C8B8,selected=0x25302D,choice_dim=0xAAAAA7,
     menu_accent=0xE4E4DF,menu_bg=0x101010,menu_dim=0x747471,menu_selected=0x353A38,menu_card=0x1C1C1C,
     grid=0x252525,grid_empty=0x101010,window=0x222222,window_cell=0x151515},
    {bright=0xF5F5F5,body=0xD2D2D2,dim=0xA0A0A0,faint=0x686868,
     rule=0x303030,track=0x262626,fill=0xC0C0C0,tab=0x151515,tab_active=0x3A3A3A,tab_dim=0x949494,
     card=0x1C1C1C,card_dim=0xA0A0A0,card_body=0xDDDDDD,card_rule=0x444444,
     accent=0xEEEEEE,selected=0x373737,choice_dim=0xAAAAAA,
     menu_accent=0xEEEEEE,menu_bg=0x121212,menu_dim=0x777777,menu_selected=0x404040,menu_card=0x242424,
     grid=0x292929,grid_empty=0x111111,window=0x272727,window_cell=0x191919},
    {bright=0xE0EFE0,body=0xC0CDC0,dim=0x91A191,faint=0x617061,
     rule=0x263026,track=0x1D251D,fill=0x94CE88,tab=0x101410,tab_active=0x293629,tab_dim=0x869586,
     card=0x111611,card_dim=0x91A191,card_body=0xCCDACC,card_rule=0x334333,
     accent=0x9CD78D,selected=0x243824,choice_dim=0x98AA98,
     menu_accent=0xB4DBA8,menu_bg=0x0D120D,menu_dim=0x60745B,menu_selected=0x2D4228,menu_card=0x192119,
     grid=0x202B20,grid_empty=0x0E130E,window=0x1C291C,window_cell=0x111A11},
    classic,
}
function M.apply(index: number)
    index=math.clamp(math.floor(index+.5),0,#palettes-1)
    if M.current==index then return end
    for key,color in pairs(classic) do M.ink[key]=color end
    for key,color in pairs(palettes[index+1]) do M.ink[key]=color end
    M.current=index
end
M.apply(0)
return M

end
