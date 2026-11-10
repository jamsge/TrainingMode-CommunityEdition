# 801a501c

.include "../Globals.s"

    lis r12, EventVars_Ptr @h
    lwz r12, EventVars_Ptr @l(r12)

    lwz r12, EventVars_Flags(r12)
    andi. r12, r12, EventVars_Flags_ForceGameLoop
    beq Original

    cmpwi r12, 0xff # ensure blt always true after exit
    b Exit

Original:
    cmpw r26, r27

Exit:
