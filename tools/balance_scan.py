# -*- coding: utf-8 -*-
"""手牌定价自检：跑一遍就能知道「有没有两张卡比单张更好还更便宜」。

用法（在工程根目录）：
    python tools/balance_scan.py

判据：
  1) 套利：存在两张卡（可跨卡、任意档位）合计费用 < 某一张的费用，
     且六项指标逐项都不弱、至少一项更强。
  2) 碾压：存在另一张价格更低的出牌，指标逐项不弱。

口径：价值 = 六项指标净 delta 之和；延迟效果按 1.00/0.85/0.70/0.55 折算。
想改定价规则时，改下面 RATE / DELAY_W / TIER_MULT 三个常量即可（和 版本更新0.0.4.md 同步）。
"""
import io, json, math, re, itertools, sys

GS = "scripts/game_state.gd"
METRICS = ["water_level", "vegetation", "water_quality", "fish", "birds", "community"]
TIERS = ["basic", "effective", "deep"]
TIER_MULT = {"basic": 0.5, "effective": 1.0, "deep": 2.0}     # 钱的倍数
DELAY_W = {0: 1.00, 1: 0.85, 2: 0.70, 3: 0.55}                # 延迟折算
RATE = 0.2788                                                 # 目标：每万多少点（折后）
EXEMPT = {"生态监测与科研"}                                     # 价值在指标之外的卡


def gr(x):
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def load(path=GS):
    t = io.open(path, encoding="utf-8").read()
    b = t[t.index("const ACTION_CARDS := ["):]
    b = b[:b.index("\n]") + 2]
    b = re.sub(r"#.*", "", b)
    b = re.sub(r",(\s*[\}\]])", r"\1", b)
    return json.loads(b[b.index("["):])


def main():
    cards = load()
    plays = []
    for c in cards:
        for t in TIERS:
            vec = {m: 0.0 for m in METRICS}
            for e in c["tiers"][t]["effects"]:
                vec[e["metric"]] += e["delta"] * DELAY_W[e["delay"]]
            cost = max(1, gr(c["cost"] * TIER_MULT[t]))
            plays.append((c["name"], t, cost, vec))
    print("卡数 %d，出牌 %d 种" % (len(cards), len(plays)))

    arb, dom, cases, doms = 0, 0, [], []
    for p3 in plays:
        if p3[0] in EXEMPT:
            continue
        for p1, p2 in itertools.combinations(plays, 2):
            if p1[0] == p2[0] or p1[2] + p2[2] >= p3[2]:
                continue
            s = {m: p1[3][m] + p2[3][m] for m in METRICS}
            if all(s[m] >= p3[3][m] - 1e-9 for m in METRICS) and any(s[m] > p3[3][m] + 1e-9 for m in METRICS):
                arb += 1
                cases.append((p3[2] - p1[2] - p2[2],
                              "%s·%s(%d万) ← %s·%s(%d万)+%s·%s(%d万)"
                              % (p3[0], p3[1], p3[2], p1[0], p1[1], p1[2], p2[0], p2[1], p2[2])))
                break
    for a in plays:
        if a[0] in EXEMPT:
            continue
        for b in plays:
            if a[0] == b[0] or a[2] <= b[2]:
                continue
            if all(b[3][m] >= a[3][m] - 1e-9 for m in METRICS) and any(b[3][m] > a[3][m] + 1e-9 for m in METRICS):
                dom += 1
                doms.append("%s·%s(%d万) ← %s·%s(%d万)" % (a[0], a[1], a[2], b[0], b[1], b[2]))
                break

    print("套利 %d / %d，碾压 %d  （已排除 %s）"
          % (arb, len(plays), dom, "、".join(EXEMPT) if EXEMPT else "无"))
    if cases:
        mx = max(s for s, _ in cases)
        print("最大套利额：%d 万  ← 大于 5 万就说明定价出了新漏洞" % mx)
        for s, x in sorted(cases, reverse=True)[:10]:
            print("   省 %d 万  %s" % (s, x))
    for x in doms[:10]:
        print("   碾压 %s" % x)

    # 性价比分布
    rates = []
    for c in cards:
        for t in TIERS:
            v = sum(e["delta"] * DELAY_W[e["delay"]] for e in c["tiers"][t]["effects"])
            cost = max(1, gr(c["cost"] * TIER_MULT[t]))
            if v > 0:
                rates.append(v / cost)
    if rates:
        print("点/万 分布：%.3f ~ %.3f（中位 %.3f）" % (min(rates), max(rates), sorted(rates)[len(rates) // 2]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
