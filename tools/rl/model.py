"""The learning AI's brain: an attention network over the game's entities that
gives orders as {actor, verb, object, target} (see scripts/game/RLAgent.gd).

Nothing here knows the game's content. Entities, objects (ships, buildings,
techs...) and targets arrive as feature rows; the network encodes them and
scores them by pointer attention, so new units or rules are just new rows.

Each step it fills SLOTS order slots. A slot first picks an actor (or "skip"),
then a verb from that actor's mask, then - only if the verb needs them - an
object of the right kind and a target.
"""
import math
import torch
import torch.nn as nn
import torch.nn.functional as F

VERBS = ["stop", "move", "attack_move", "attack", "mine", "return", "colonize", "bombard",
         "dock", "refit", "found", "ability", "build_ship", "cancel_ship", "rally",
         "build_building", "cancel_building", "demolish", "research", "cancel_research"]
OBJ_KINDS = ["ship", "building", "construct", "tech"]
# Which object kind a verb takes (index into OBJ_KINDS), and which verbs take a target.
VERB_OBJ = {"build_ship": 0, "build_building": 1, "demolish": 1, "found": 2, "research": 3}
VERB_TGT = {"move", "attack_move", "attack", "mine", "return", "colonize", "bombard", "dock", "refit", "found", "rally"}
## Orders per decision. Cut from 8 to 4 (update 2300): it was filling ~7 of 8
## with single-ship orders; fewer slots make it choose what matters, and a
## group order is the cheap way to move many ships.
SLOTS = 4
## Starting odds of "no new order" vs giving one, per slot (4 -> ~1.6 orders a decision).
SKIP_ODDS = 4.0
NEG = -1e9


def collate(obs_list, device):
    """Pads a list of observations into batch tensors."""
    B = len(obs_list)
    E = max(1, max(len(o["entities"]) for o in obs_list))
    P = max(1, max(len(o["targets"]) for o in obs_list))
    A = max(1, max(len(o["actors"]) for o in obs_list))
    O = max(1, max(len(o["objects"]) for o in obs_list))
    fe = len(obs_list[0]["entities"][0]) if obs_list[0]["entities"] else 27
    fo = len(obs_list[0]["objects"][0])
    fs = len(obs_list[0]["self"])
    ent = torch.zeros(B, E, fe); ent_m = torch.zeros(B, E, dtype=torch.bool)
    pts = torch.zeros(B, P, fe); pts_m = torch.zeros(B, P, dtype=torch.bool)
    obj = torch.zeros(B, O, fo); obj_m = torch.zeros(B, O, dtype=torch.bool)
    act_ent = torch.full((B, A), -1, dtype=torch.long); act_m = torch.zeros(B, A, dtype=torch.bool)
    act_grp = torch.zeros(B, A)   # group size (0 = a single unit)
    vmask = torch.zeros(B, A, len(VERBS), dtype=torch.bool)
    me = torch.zeros(B, fs)
    for b, o in enumerate(obs_list):
        if o["entities"]:
            t = torch.tensor(o["entities"], dtype=torch.float32); ent[b, :len(t)] = t; ent_m[b, :len(t)] = True
        if o["targets"]:
            t = torch.tensor(o["targets"], dtype=torch.float32); pts[b, :len(t)] = t; pts_m[b, :len(t)] = True
        t = torch.tensor(o["objects"], dtype=torch.float32); obj[b, :len(t)] = t; obj_m[b, :len(t)] = True
        for i, a in enumerate(o["actors"]):
            act_ent[b, i] = a["entity"]; act_m[b, i] = True
            act_grp[b, i] = a.get("group", 0)
            vmask[b, i] = torch.tensor(a["mask"], dtype=torch.bool)
        me[b] = torch.tensor(o["self"], dtype=torch.float32)
    d = dict(ent=ent, ent_m=ent_m, pts=pts, pts_m=pts_m, obj=obj, obj_m=obj_m,
             act_ent=act_ent, act_m=act_m, act_grp=act_grp, vmask=vmask, me=me)
    return {k: v.to(device) for k, v in d.items()}


class Policy(nn.Module):
    def __init__(self, f_ent=27, f_obj=53, f_self=13, d=96, layers=2, heads=4):
        super().__init__()
        self.ent_in = nn.Linear(f_ent, d)
        self.obj_in = nn.Sequential(nn.Linear(f_obj, d), nn.ReLU(), nn.Linear(d, d))
        self.self_in = nn.Linear(f_self, d)
        enc = nn.TransformerEncoderLayer(d, heads, d * 2, dropout=0.0, batch_first=True)
        self.encoder = nn.TransformerEncoder(enc, layers)
        self.slot = nn.Parameter(torch.randn(SLOTS, d) * 0.1)
        self.empire = nn.Parameter(torch.randn(d) * 0.1)
        self.skip = nn.Parameter(torch.randn(d) * 0.1)
        self.group = nn.Parameter(torch.randn(d) * 0.1)
        self.group_size = nn.Parameter(torch.randn(d) * 0.02)
        self.verb_emb = nn.Embedding(len(VERBS), d)
        self.q_actor = nn.Linear(2 * d, d)
        self.verb_head = nn.Sequential(nn.Linear(3 * d, d), nn.ReLU(), nn.Linear(d, len(VERBS)))
        self.q_obj = nn.Sequential(nn.Linear(4 * d, d), nn.ReLU(), nn.Linear(d, d))
        self.q_tgt = nn.Sequential(nn.Linear(5 * d, d), nn.ReLU(), nn.Linear(d, d))
        self.value = nn.Sequential(nn.Linear(2 * d, d), nn.ReLU(), nn.Linear(d, 1))
        self.d = d

    def encode(self, x):
        B = x["ent"].shape[0]
        me = self.self_in(x["me"]).unsqueeze(1)                      # [B,1,d]
        tok = torch.cat([me, self.ent_in(x["ent"]), self.ent_in(x["pts"])], 1)
        mask = torch.cat([torch.ones(B, 1, dtype=torch.bool, device=me.device), x["ent_m"], x["pts_m"]], 1)
        h = self.encoder(tok, src_key_padding_mask=~mask)
        g = torch.cat([h[:, 0], (h * mask.unsqueeze(-1)).sum(1) / mask.sum(1, keepdim=True)], -1)  # [B,2d]
        E = x["ent"].shape[1]
        ents, pts = h[:, 1:1 + E], h[:, 1 + E:]
        # Actor tokens: the entity's encoding, or the learned empire token.
        idx = x["act_ent"].clamp(min=0)
        actors = torch.gather(ents, 1, idx.unsqueeze(-1).expand(-1, -1, self.d))
        actors = torch.where((x["act_ent"] < 0).unsqueeze(-1), self.empire.expand_as(actors), actors)
        # A group order: the lead ship's encoding, marked as a group and its size.
        grp = x["act_grp"].unsqueeze(-1)
        actors = actors + (grp > 0).float() * self.group + torch.log1p(grp) * self.group_size
        targets = torch.cat([ents, pts], 1)
        tgt_m = torch.cat([x["ent_m"], x["pts_m"]], 1)
        objs = self.obj_in(x["obj"])
        return g, actors, targets, tgt_m, objs

    def forward(self, x, act=None):
        """Samples SLOTS orders (or scores the given ones). Returns orders
        [B,SLOTS,4] (actor -1 = skip), their summed log-prob [B], entropy [B]
        and the value [B]."""
        g, actors, targets, tgt_m, objs = self.encode(x)
        B, A = x["act_m"].shape
        value = self.value(g).squeeze(-1)
        dev = g.device
        logp = torch.zeros(B, device=dev); ent = torch.zeros(B, device=dev)
        out = torch.full((B, SLOTS, 4), -1, dtype=torch.long, device=dev)
        obj_kind = x["obj"][..., :len(OBJ_KINDS)].argmax(-1)          # [B,O]
        obj_ok = x["obj_m"] & (x["obj"][..., len(OBJ_KINDS)] > 0.5)
        for s in range(SLOTS):
            sl = self.slot[s].expand(B, -1)
            # Actor (index A = skip).
            q = self.q_actor(torch.cat([g[:, :self.d] + sl, g[:, self.d:]], -1))
            cand = torch.cat([actors, self.skip.expand(B, 1, -1)], 1)
            lg = (cand @ q.unsqueeze(-1)).squeeze(-1) / self.d ** 0.5
            ok = torch.cat([x["act_m"] & x["vmask"].any(-1), torch.ones(B, 1, dtype=torch.bool, device=dev)], 1)
            # "No new order" is the default: skip starts SKIP_ODDS times as
            # likely as all the actors together, so units keep their tasks
            # unless an order is worth giving (learning can shift this).
            n_ok = ok[:, :-1].sum(-1).clamp(min=1).float()
            lg = torch.cat([lg[:, :-1], lg[:, -1:] + math.log(SKIP_ODDS) + n_ok.log().unsqueeze(-1)], 1)
            lg = lg.masked_fill(~ok, NEG)
            dist = torch.distributions.Categorical(logits=lg)
            a = dist.sample() if act is None else act[:, s, 0].where(act[:, s, 0] >= 0, torch.full_like(act[:, s, 0], A))
            logp += dist.log_prob(a); ent += dist.entropy()
            live = a < A
            ai = a.clamp(max=A - 1)
            a_tok = actors[torch.arange(B), ai]
            # Verb from that actor's mask.
            vl = self.verb_head(torch.cat([a_tok, g], -1))
            vm = x["vmask"][torch.arange(B), ai]
            vm = vm | ~live.unsqueeze(-1)      # skip: anything (ignored)
            vl = vl.masked_fill(~vm, NEG)
            vd = torch.distributions.Categorical(logits=vl)
            v = vd.sample() if act is None else act[:, s, 1].clamp(min=0)
            logp += vd.log_prob(v) * live; ent += vd.entropy() * live
            v_tok = self.verb_emb(v)
            # Object, for verbs that take one, from objects of the right kind.
            need_o = torch.tensor([VERB_OBJ.get(VERBS[i], -1) for i in range(len(VERBS))], device=dev)[v]
            has_o = live & (need_o >= 0)
            qo = self.q_obj(torch.cat([a_tok, v_tok, g], -1))
            ol = (objs @ qo.unsqueeze(-1)).squeeze(-1) / self.d ** 0.5
            om = obj_ok & (obj_kind == need_o.unsqueeze(-1))
            om = om | ~has_o.unsqueeze(-1)
            any_o = om.any(-1)
            ol = ol.masked_fill(~om, NEG)
            od = torch.distributions.Categorical(logits=ol)
            o = od.sample() if act is None else act[:, s, 2].clamp(min=0)
            has_o = has_o & any_o
            logp += od.log_prob(o) * has_o; ent += od.entropy() * has_o
            o_tok = objs[torch.arange(B), o] * has_o.unsqueeze(-1)
            # Target, for verbs that take one.
            need_t = torch.tensor([VERBS[i] in VERB_TGT for i in range(len(VERBS))], device=dev)[v]
            has_t = live & need_t
            qt = self.q_tgt(torch.cat([a_tok, v_tok, o_tok, g], -1))
            tl = (targets @ qt.unsqueeze(-1)).squeeze(-1) / self.d ** 0.5
            tl = tl.masked_fill(~tgt_m, NEG)
            td = torch.distributions.Categorical(logits=tl)
            # Targets are padded as [entities..pad, points..pad]; orders use
            # each game's own numbering [its entities, its points].
            e_pad = x["ent"].shape[1]
            e_own = x["ent_m"].sum(1)
            if act is None:
                t = td.sample()
                t_out = torch.where(t < e_pad, t, t - e_pad + e_own)
            else:
                t_out = act[:, s, 3].clamp(min=0)
                t = torch.where(t_out < e_own, t_out, t_out - e_own + e_pad)
            logp += td.log_prob(t) * has_t; ent += td.entropy() * has_t
            out[:, s, 0] = torch.where(live, ai, torch.full_like(ai, -1))
            out[:, s, 1] = v
            out[:, s, 2] = torch.where(has_o, o, torch.full_like(o, -1))
            out[:, s, 3] = torch.where(has_t, t_out, torch.full_like(t_out, -1))
        return out, logp, ent, value
