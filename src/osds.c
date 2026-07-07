#include "osds.h"


static void UpdateIASATracking(GOBJ *ft) {
    FighterData *ft_data = ft->userdata;
    if (ft_data->flags.past_iasa)
        ft_data->TM.iasa_frames++;
    else
        ft_data->TM.iasa_frames = 0;
}

static bool CheckIASA(FighterData *data) {
    // The spotdodge state is weird - its subaction list contains an IASA event which sets the IASA bit,
    // but the initial state entry function does not clear the flag.
    // This causes it to not function - the player can't cancel it,
    // but it causes us to think they can if it is performed after a state that clears the iasa bit (e.g. landing with an aerial).
    if (data->state_id == ASID_ESCAPE)
        return false;

    // For some reason, the iasa flag isn't reset when the state changes, only when a new action that has iasa starts.
    // So we need to do some bs tracking to figure out if the character is in iasa.
    return data->TM.iasa_frames && data->TM.iasa_frames <= data->TM.state_frame;
}

static void RunOSD_FrameAdvantage(GOBJ *ft, GOBJ *ft_sub) {
    /*
    Detect when your shield is hit. This is ez, look for GuardSetOff.
        If the attacker is actionable and the defender is not,
            the advantage is the # frames until shieldstun is gone.
        If the attacker is actionable and the defender is also actionable,
            the advantages is -frames since shieldstun.

    We use the 0 state to wait for GuardSetOff to start.
    We use the -1 state to wait for GuardSetOff to end.
    */

    FighterData *ft_data = ft->userdata;
    FighterData *ft_def_data = ft_data->TM.fighter_hurt_shield;
    if (ft_def_data == 0) return;
    GOBJ *ft_def = ft_def_data->fighter;

    int ply = ft_data->ply;
    static int atk_hit_state[6] = {0};

    // Wait for GuardSetOff to end before running frame advantage code again
    if (atk_hit_state[ply] == -1) {
        if (ft_def_data->state_id != ASID_GUARDSETOFF)
            atk_hit_state[ply] = 0;
        return;
    }

    // Detect when the defender's shield is hit and save the attacker's state
    if (atk_hit_state[ply] == 0) {
        if (ft_def_data->state_id == ASID_GUARDSETOFF)
            atk_hit_state[ply] = ft_data->state_id;
        return;
    }

    int atk_state = ft_data->state_id;

    // "actionable" if either state changed or in iasa, and not in aerial or ac landing lag.
    bool atk_actionable = (atk_hit_state[ply] != atk_state || CheckIASA(ft_data))
        && (atk_state != ASID_LANDING || ft_data->state.frame >= ft_data->attr.normal_landing_lag)
        && (atk_state < ASID_LANDINGAIRN || ASID_LANDINGAIRLW < atk_state);

    if (atk_actionable) {
        int advantage;

        if (ft_def_data->state_id == ASID_GUARDSETOFF) {
            // + on shield: advantage is frames until shieldstun is gone.
            float anim_speed = ft_def_data->state.rate;
            float stun_total = JOBJ_GetJointAnimFrameTotal(ft_def->hsd_object);
            float stun_curr = ft_def_data->state.frame;
            advantage = (int)((stun_total - stun_curr) / anim_speed) + 1;
        } else {
            // = or - on shield: advantage is -frames since shieldstun.
            advantage = -(int)ft_def_data->TM.state_frame;
            for (u32 i = 0; i < countof(ft_def_data->TM.state_prev); ++i) {
                if (ft_def_data->TM.state_prev[i] == ASID_GUARDSETOFF)
                    break;
                advantage -= (int)ft_def_data->TM.state_prev_frames[i];
            }
            advantage += 1; // off-by-one
        }

        Message_Display(
            OSD_FrameAdvantage, ft_data->ply,
            advantage > -7 ? MSGCOLOR_GREEN : MSGCOLOR_WHITE,
            "Frame Advantage\n%d Frames", advantage
        );

        // Wait until GuardSetOff finishes
        atk_hit_state[ply] = -1;
    }
}

static void RunOSD_Wavedash(GOBJ *ft, GOBJ *ft_sub) {
    FighterData *ft_data = ft->userdata;
    OSD_WavedashData *osd_data = &wavedash_osd_data;
    // start sequence on jump squat
    if (ft_data->state_id == ASID_KNEEBEND && ft_data->TM.state_frame == 0)
    {
        osd_data->timer = 0;
        osd_data->airdodge_frame = -1;
    }

    // do nothing if sequence hasn't started
    if (osd_data->timer < 0)
        return;

    // run sequence logic
    osd_data->timer++;

    // The game tracks whether the current jump is going to be a short hop in
    // `state_var1`. The value at the end of kneebend is what we want.
    if (ft_data->state_id == ASID_KNEEBEND)
        osd_data->short_hop = ft_data->state_var.state_var1;

    // Record early airdodge timings. May be overwritten by a later successful
    // timing in case player uses multiple presses.
    if (ft_data->input.down & (PAD_TRIGGER_L | PAD_TRIGGER_R) &&
            ft_data->state_id == ASID_KNEEBEND)
        osd_data->airdodge_frame = osd_data->timer;

    // real airdodge
    if (ft_data->TM.state_frame == 0 &&
            (ft_data->state_id == ASID_ESCAPEAIR ||
            (ft_data->state_id == ASID_LANDINGFALLSPECIAL &&
             ft_data->TM.state_prev[0] == ASID_ESCAPEAIR &&
             ft_data->TM.state_prev_frames[0] == 0)))
    {
        osd_data->airdodge_frame = osd_data->timer;
        Vec2 lstick = ft_data->input.lstick;
        osd_data->angle_real = -atan2(lstick.Y, fabs(lstick.X)) / M_1DEGREE;

        PADStatus *stat = PadGetRaw(0);
        osd_data->angle_raw = -atan2(stat->stickY, fabs(stat->stickX)) / M_1DEGREE;
    }

    if (ft_data->TM.state_frame >= FAILFRAMES &&
             osd_data->airdodge_frame > 0 &&
            (ft_data->state_id == ASID_JUMPF ||
             ft_data->state_id == ASID_JUMPB ||
             ft_data->state_id == ASID_ESCAPEAIR)) {
        // failure
        return;
    }
    else if (ft_data->state_id == ASID_KNEEBEND ||
              (ft_data->TM.state_frame < FAILFRAMES &&
              (ft_data->state_id == ASID_JUMPF ||
               ft_data->state_id == ASID_JUMPB ||
               ft_data->state_id == ASID_ESCAPEAIR))) {
        // in progress
        return;
    }

    // Reset
    osd_data->timer = -1;

    // Wavedash not attempted
    if (osd_data->airdodge_frame < 0)
        return;

    int timing = osd_data->airdodge_frame - (int)ft_data->attr.jump_startup_time - 1;

    GOBJ *Message_GOBJ = Message_Display(
        OSD_Wavedash, ft_data->ply,
        MSGCOLOR_WHITE,
        "WD Frame: %df\nAngle: %.1f\n%s",
        timing,
        osd_data->angle_real,
        osd_data->short_hop ? "Short Hop" : "Full Hop"
    );

    GXColor *color = &text_white;
    MsgData *msg_data = Message_GOBJ->userdata;
    if (timing == 0)
        color = &text_green;
    Text_SetColor(msg_data->text, 0, color);

    if (osd_data->angle_real <= 23.7f && osd_data->angle_real>=16.8)
        color = &text_gold;
    else if (osd_data->angle_real <= 30.5)
        color = &text_green;
    else
        color = &text_white;
    Text_SetColor(msg_data->text, 1, color);
}

void OSD_Think(GOBJ *event) {
    u32 osd_enabled = stc_memcard->TM_OSDEnabled;

    for (int ply = 0; ply < 6; ++ply) {
        GOBJ *ft = Fighter_GetSubcharGObj(ply, 0);
        if (!ft) continue;

        // subchar is usually null except for nana and the inactive sheik/zelda tform
        GOBJ *ft_sub = Fighter_GetSubcharGObj(ply, 1);

        if (ft) UpdateIASATracking(ft);
        if (ft_sub) UpdateIASATracking(ft_sub);

        if (osd_enabled & (1u << OSD_FrameAdvantage)) RunOSD_FrameAdvantage(ft, ft_sub);
        if (osd_enabled & (1u << OSD_Wavedash)) RunOSD_Wavedash(ft, ft_sub);
    }
}
