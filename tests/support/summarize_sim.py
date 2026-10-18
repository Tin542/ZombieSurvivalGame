"""Summarise tests/balance_sim.gd output.

Usage: python3 tests/support/summarize_sim.py <dir with *.jsonl> [--waves]

One row per profile/skill:
  wave      median wave the bot died in. A run that survived to --max-wave
            ("capped") counts as that last wave and the cell is marked
            ">=" with the number of capped runs, since its true value is higher.
  coins     median coins per run; coins/w divides by the waves actually played.
With --waves, per-wave medians over the runs that CLEARED that wave (the wave a
run died in is left out of the medians and counted in the "died" column):
combat seconds, damage taken, lowest HP, medkits used, coins, crates, loot
dropped, lowest bag ammo, bag at the end of the wave; "ammo<60" counts the runs
whose bag ammo fell below 60 during the wave.
"""
import glob
import json
import os
import statistics as st
import sys

ORDER = ['fresh', 'smg', 'mid', 'late']


def med(xs):
    return st.median(xs) if xs else 0


def med_dict(dicts):
    keys = sorted({k for d in dicts for k in d})
    return {k: round(med([d.get(k, 0) for d in dicts]), 1) for k in keys}


def last_wave(r):
    # Older output had no last_wave; a capped run's wave_reached was max_wave + 1.
    return r.get('last_wave', r['wave_reached'] - (1 if r.get('capped') else 0))


def main():
    directory = sys.argv[1]
    show_waves = '--waves' in sys.argv
    rows = []
    for path in sorted(glob.glob(os.path.join(directory, '*.jsonl'))):
        with open(path) as f:
            rows += [json.loads(line) for line in f if line.strip()]
    groups = {}
    for r in rows:
        groups.setdefault((r['profile'], r['skill']), []).append(r)
    keys = sorted(groups, key=lambda k: (ORDER.index(k[0]) if k[0] in ORDER else 9, k[1]))

    print(f"{'profile/skill':16} {'runs':>4} {'wave(med)':>10} {'min-max':>8} {'coins':>6} {'coins/w':>7} {'kills':>6} {'tick ms':>7}")
    for key in keys:
        rs = groups[key]
        waves = [last_wave(r) for r in rs]
        caps = sum(1 for r in rs if r.get('capped'))
        stuck = sum(1 for r in rs if r.get('abandoned'))
        wave_text = ('>=' if caps else '') + f"{med(waves):g}"
        note = (f"  ({caps} capped)" if caps else '') + (f"  ({stuck} ABANDONED)" if stuck else '')
        print(f"{key[0] + '/' + key[1]:16} {len(rs):>4} {wave_text:>10} {str(min(waves)) + '-' + str(max(waves)):>8} "
              f"{med([r['coins'] for r in rs]):>6.0f} {med([r['coins'] / max(last_wave(r), 1) for r in rs]):>7.1f} "
              f"{med([r['kills'] for r in rs]):>6.0f} {med([r['tick_ms_avg'] for r in rs]):>7.2f}{note}")

    if not show_waves:
        return
    for key in keys:
        rs = groups[key]
        print(f"\n== {key[0]}/{key[1]}  per wave (medians over runs that cleared the wave)")
        print(f"{'w':>3} {'n':>2} {'died':>4} {'combat s':>8} {'dmg':>5} {'minhp':>5} {'meds':>4} {'coins':>5} "
              f"{'crH':>3} {'crA':>3} {'ammo<60':>7} {'loot dropped (units)':38} {'ammo min':20} bag end")
        for i in range(max(len(r['waves']) for r in rs)):
            records = [r['waves'][i] for r in rs if len(r['waves']) > i and not r['waves'][i].get('unfinished')]
            if not records:
                continue
            died = sum(1 for w in records if w.get('died'))
            ws = [w for w in records if not w.get('died')]
            if not ws:
                print(f"{records[0]['wave']:>3} {0:>2} {died:>4}")
                continue
            loot = {}
            for w in ws:
                for k, v in w['loot_dropped'].items():
                    loot[k] = loot.get(k, 0) + v
            loot = {k: round(v / len(ws), 1) for k, v in sorted(loot.items())}
            low = sum(1 for w in ws if any(v < 60 for v in w.get('ammo_min', {}).values()))
            print(f"{ws[0]['wave']:>3} {len(ws):>2} {died:>4} {med([w['combat_seconds'] for w in ws]):>8.0f} "
                  f"{med([w['damage_taken'] for w in ws]):>5.0f} {med([w['min_hp_ratio'] for w in ws]):>5.2f} "
                  f"{med([w['medkits_used'] for w in ws]):>4g} {med([w['coins'] for w in ws]):>5.0f} "
                  f"{med([w['crates_health'] for w in ws]):>3.0f} {med([w['crates_ammo'] for w in ws]):>3.0f} "
                  f"{str(low) + '/' + str(len(ws)):>7} {str(loot):38} {str(med_dict([w.get('ammo_min', {}) for w in ws])):20} "
                  f"{med_dict([w['bag_end'] for w in ws])}")


if __name__ == '__main__':
    main()
