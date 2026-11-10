    # To be inserted at 8000551c
    .include "../../../Globals.s"
    .include "../../../m-ex/Header.s"

    .set playerdata, 31
    .set player, 30
    .set FramesSince, 28
    .set ASBeforeWait, 27
    .set OSDText, 26

    backupall

    # Get Player Pointers
    mr player, r3
    lwz playerdata, 0x2c(player)

CheckForFollower:
    mr r3, playerdata
    branchl r12, 0x80005510
    cmpwi r3, 0x1
    beq Exit

    # Calculate Frames Since Wait and Get AS Before Wait
    li r5, 0                                    # Loop Count
    li r4, TM_PrevASStart

WaitSearchLoop:
    mulli r3, r5, 0x2
    add r3, r3, r4
    lhzx r3, r3, playerdata
    
    cmpwi r3, ASID_Wait
    beq WaitSearchExit_Wait
    
    cmpwi r3, ASID_Landing
    beq WaitSearchExit_Landing
    
    addi r5, r5, 1
    cmpwi r5, 6
    bge Exit
    b WaitSearchLoop
    
WaitSearchExit_Landing:
    bl AutocancelTextEnd
    .string "Act OoAutocancel\nFrame: %d"
    .align 2
AutocancelTextEnd:
    mflr OSDText
    li FramesSince, -3
    b WaitSearchExit
    
WaitSearchExit_Wait:
    bl WaitTextEnd
    .string "Act OoWait\nFrame: %d"
    .align 2
WaitTextEnd:
    mflr OSDText
    li FramesSince, 1

WaitSearchExit:
    # Get AS Before Wait
    addi r3, r5, 1
    mulli r3, r3, 0x2
    add r3, r3, r4
    lhzx ASBeforeWait, r3, playerdata
    # Get Frames In Wait
    
    li r4, TM_FramesInPrevASStart               # Frame Count Start
FrameCountLoop:
    cmpwi r5, 0
    blt FrameCountLoopFinish
    mulli r3, r5, 0x2
    add r3, r3, r4
    
    subi r6, r3, 12
    lhzx r6, r6, playerdata
    
    # Subtract 1 unavoidable frame if in Turn
    cmpwi r6, ASID_Turn
    bne TurnFinish
    subi FramesSince, FramesSince, 1
TurnFinish:

    # Remove psuedo Wait frame
    cmpwi r6, ASID_Wait
    bne WaitFinish
    subi FramesSince, FramesSince, 1
WaitFinish:

    lhzx r3, r3, playerdata
    add FramesSince, r3, FramesSince
    subi r5, r5, 1
    b FrameCountLoop

FrameCountLoopFinish:
    # Check If Under 13 Frames
    cmpwi FramesSince, 13
    bgt Exit

    # Only Coming from Throws, Aerial Landing, and Teching/Getups
    # Aerial Landing
    cmpwi ASBeforeWait, ASID_LandingAirN
    blt NotAerialLanding
    cmpwi ASBeforeWait, ASID_LandingAirLw
    bgt NotAerialLanding
    b ComingFromWhitelist
NotAerialLanding:

    # Throws
    cmpwi ASBeforeWait, ASID_ThrowF
    blt NotThrow
    cmpwi ASBeforeWait, ASID_ThrowLw
    bgt NotThrow
    b ComingFromWhitelist
NotThrow:

    # Teching/Getups
    cmpwi ASBeforeWait, ASID_DownBoundU
    blt NotTeching
    cmpwi ASBeforeWait, ASID_PassiveStandB
    bgt NotTeching
    b ComingFromWhitelist
NotTeching:

    # Wavedash
    cmpwi ASBeforeWait, ASID_LandingFallSpecial
    bne NotWavedash
    b ComingFromWhitelist
NotWavedash:

    # Laser
    cmpwi ASBeforeWait, 341
    blt NotLaser
    cmpwi ASBeforeWait, 346
    bgt NotLaser
    lwz r3, 0x4(playerdata)  # fighter id
    cmpwi r3, Fox.Int
    beq ComingFromWhitelist
    cmpwi r3, Falco.Int
    beq ComingFromWhitelist
NotLaser:

    # Needles
    cmpwi ASBeforeWait, 341
    blt NotNeedles
    cmpwi ASBeforeWait, 348
    bgt NotNeedles
    lwz r3, 0x4(playerdata)  # fighter id
    cmpwi r3, Sheik.Int
    beq ComingFromWhitelist
NotNeedles:

    # FC Aerials
    cmpwi ASBeforeWait, 344
    blt NotFCAerial
    cmpwi ASBeforeWait, 348
    bgt NotFCAerial
    lwz r3, 0x4(playerdata)  # fighter id
    cmpwi r3, Peach.Int
    beq ComingFromWhitelist
NotFCAerial:

    cmpwi ASBeforeWait, ASID_AttackAirN
    blt NotAerial
    cmpwi ASBeforeWait, ASID_AttackAirLw
    bgt NotAerial
    b ComingFromWhitelist
NotAerial:

    b Exit

ComingFromWhitelist:
SpawnText:
    # Change Text Color
    cmpwi FramesSince, 0x1
    bne RedText

GreenText:
    load r3, 0x8dff6eff                         # green
    b StoreTextColor

RedText:
    load r3, 0xffa2baff

StoreTextColor:
    stw r3, 0x80(sp)

    # Create Text
    li r3, 5                                    # Message Kind
    lbz r4, 0xC(playerdata)                     # Message Queue
    li r5, MSGCOLOR_WHITE
    mr r6, OSDText
    mr r7, FramesSince
    Message_Display

ChangeColor:
    lwz r3, 0x2C(r3)
    lwz r3, MsgData_Text(r3)
    li r4, 1
    addi r5, sp, 0x80
    branchl r12, Text_ChangeTextColor

    b Exit

Exit:
    restoreall
    blr
