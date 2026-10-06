import json
import os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# ============================================
# CONFIG
# ============================================
BASE = os.path.expanduser('~/iperf_results/testbed/exp3')
OUT  = os.path.expanduser('~/iperf_results/testbed/exp3/plots')
os.makedirs(OUT, exist_ok=True)

QOS = {
    'mmtc':  {'tp': 1.0,       'jitter': None, 'loss': 1.0,
               'tp_unit': 'kbps', 'label': 'mMTC (UC2/UC6)',
               'ue': 'UE1'},
    'embb':  {'tp': 120000.0,  'jitter': 20.0, 'loss': 0.01,
               'tp_unit': 'kbps', 'label': 'eMBB (UC6/UC8)',
               'ue': 'UE3'},
    'urllc': {'tp': 28.0,      'jitter': 40.0, 'loss': 0.1,
               'tp_unit': 'kbps', 'label': 'URLLC (UC8)',
               'ue': 'UE2'},
}

# ============================================
# PARSER
# ============================================
def parse_jsonl(filepath):
    results = []
    buffer  = ''
    depth   = 0
    try:
        with open(filepath, 'r') as f:
            for line in f:
                buffer += line
                depth  += line.count('{') - line.count('}')
                if depth == 0 and buffer.strip():
                    try:
                        results.append(json.loads(buffer))
                        buffer = ''
                    except:
                        buffer = ''
    except FileNotFoundError:
        pass
    return [d for d in results
            if d.get('end', {}).get('sum')]

def extract(data):
    tp, jit, los = [], [], []
    for d in data:
        sr = d['end']['sum_received']
        tp.append(sr['bits_per_second']/1000)
        if 'jitter_ms' in sr:
            jit.append(sr['jitter_ms'])
        if 'lost_percent' in sr:
            los.append(sr['lost_percent'])
    return tp, jit, los

services = {
    'mmtc':  BASE,
    'embb':  BASE,
    'urllc': BASE,
}

all_data = {}
for svc, path in services.items():
    all_data[svc] = {}
    for run in range(1, 6):
        fp = os.path.join(path, f'{svc}_run_{run}.json')
        parsed = parse_jsonl(fp)
        if parsed:
            all_data[svc][run] = parsed

# ============================================
# FIRST ORDER STATS
# ============================================
print("=" * 60)
print("EXPERIMENT 3 — FIRST ORDER STATISTICS")
print("=" * 60)

summary = {}
for svc in ['mmtc', 'embb', 'urllc']:
    print(f"\n{'=' * 40}")
    print(f"SERVICE: {QOS[svc]['label']} | {QOS[svc]['ue']}")
    print(f"{'=' * 40}")

    all_tp, all_jit, all_los = [], [], []

    for run in range(1, 6):
        if run not in all_data[svc]:
            print(f"  Run {run:2d}: NO DATA")
            continue

        tp, jit, los = extract(all_data[svc][run])
        all_tp.extend(tp)
        all_jit.extend(jit)
        all_los.extend(los)

        tp_disp = (f"{np.mean(tp)/1000:.2f} Mbps"
                   if svc == 'embb'
                   else f"{np.mean(tp):.3f} kbps")

        print(f"  Run {run:2d}: "
              f"TX={len(tp):3d} | "
              f"TP={tp_disp} | "
              f"Jitter={np.mean(jit):.3f}ms | "
              f"Loss={np.mean(los):.2f}%")

    if not all_tp:
        print("  No data collected for this service")
        summary[svc] = {'tp': [], 'jit': [], 'los': []}
        continue

    # Aggregate display
    if svc == 'embb':
        tp_agg = (f"mean:{np.mean(all_tp)/1000:.2f} "
                  f"min:{np.min(all_tp)/1000:.2f} "
                  f"max:{np.max(all_tp)/1000:.2f} "
                  f"std:{np.std(all_tp)/1000:.2f} Mbps")
    else:
        tp_agg = (f"mean:{np.mean(all_tp):.3f} "
                  f"min:{np.min(all_tp):.3f} "
                  f"max:{np.max(all_tp):.3f} "
                  f"std:{np.std(all_tp):.3f} kbps")

    print(f"\n  --- AGGREGATE ({len(all_tp)} total TX) ---")
    print(f"  Throughput  — {tp_agg}")
    print(f"  Jitter      — mean:{np.mean(all_jit):.3f} "
          f"min:{np.min(all_jit):.3f} "
          f"max:{np.max(all_jit):.3f} "
          f"std:{np.std(all_jit):.3f} ms")
    print(f"  Packet loss — mean:{np.mean(all_los):.3f} "
          f"min:{np.min(all_los):.3f} "
          f"max:{np.max(all_los):.3f}%")

    summary[svc] = {
        'tp': all_tp, 'jit': all_jit, 'los': all_los
    }

# ============================================
# QoS COMPLIANCE
# ============================================
print(f"\n{'=' * 60}")
print("QoS COMPLIANCE CHECK (PA Paper Targets)")
print(f"{'=' * 60}")

for svc in ['mmtc', 'embb', 'urllc']:
    q   = QOS[svc]
    if not summary[svc]['tp']:
        print(f"\n{q['label']}: NO DATA")
        continue

    tp  = summary[svc]['tp']
    jit = summary[svc]['jit']
    los = summary[svc]['los']

    print(f"\n{q['label']} ({q['ue']}):")

    # Throughput compliance
    tp_target = q['tp']
    if svc == 'mmtc':
    	tp_ok = sum(1 for t in tp if t <= tp_target * 1.1)  # ceiling, with 10% tolerance
    else:
    	tp_ok = sum(1 for t in tp if t >= tp_target * 0.9)  # floor
    tp_mean_disp = (f"{np.mean(tp)/1000:.2f} Mbps"
                    if svc == 'embb'
                    else f"{np.mean(tp):.3f} kbps")
    tp_target_disp = (f"{tp_target/1000:.0f} Mbps"
                      if svc == 'embb'
                      else f"{tp_target} kbps")
    print(f"  Throughput  target: {tp_target_disp} | "
          f"achieved: {tp_mean_disp} | "
          f"compliant: {tp_ok}/{len(tp)} "
          f"({tp_ok/len(tp)*100:.1f}%)")

    # Jitter compliance
    if q['jitter']:
        jit_ok = sum(1 for j in jit if j < q['jitter'])
        print(f"  Jitter      target: <{q['jitter']}ms | "
              f"achieved: {np.mean(jit):.3f}ms | "
              f"compliant: {jit_ok}/{len(jit)} "
              f"({jit_ok/len(jit)*100:.1f}%)")
    else:
        print(f"  Jitter      no hard target | "
              f"mean: {np.mean(jit):.3f}ms")

    # Packet loss compliance
    los_ok = sum(1 for l in los if l <= q['loss'])
    print(f"  Packet loss target: <{q['loss']}% | "
          f"achieved: {np.mean(los):.3f}% | "
          f"compliant: {los_ok}/{len(los)} "
          f"({los_ok/len(los)*100:.1f}%)")

# ============================================
# PLOTS 
# ============================================
fig, axes = plt.subplots(3, 3, figsize=(16, 14))
fig.suptitle('Experiment 3 - Aggregated Traffic\n'
             'mMTC, eMBB, and URLLC QoS Performance',
             fontsize=13, fontweight='bold')

colors = {
    'mmtc':  'steelblue',
    'embb':  'darkorange',
    'urllc': 'crimson'
}
titles = {
    'mmtc':  'mMTC — UE1 (Soil Sensor)',
    'embb':  'eMBB — UE3 (Drone Video)',
    'urllc': 'URLLC — UE2 (C2 Link)'
}

for row, svc in enumerate(['mmtc', 'urllc', 'embb']):
    if not summary[svc]['tp']:
        for col in range(3):
            axes[row, col].text(0.5, 0.5, 'No data',
                                ha='center', va='center',
                                transform=axes[row, col].transAxes)
            axes[row, col].set_title(
                f'{titles[svc]}\nNo data collected')
        continue

    tp  = summary[svc]['tp']
    jit = summary[svc]['jit']
    los = summary[svc]['los']
    c   = colors[svc]
    q   = QOS[svc]

    tp_plot = [t/1000 for t in tp] if svc == 'embb' else tp
    tp_target_plot = q['tp']/1000 if svc == 'embb' else q['tp']
    tp_ylabel = ('Throughput (Mbps)'
                 if svc == 'embb'
                 else 'Throughput (kbps)')
    tp_target_label = (f"Target {q['tp']/1000:.0f} Mbps"
                       if svc == 'embb'
                       else f"Target {q['tp']} kbps")

    # Plot 1 — Throughput per transmission
    axes[row, 0].plot(tp_plot, color=c,
                      linewidth=0.8, alpha=0.7,
                      label='Measured')
    axes[row, 0].axhline(y=tp_target_plot, color='red',
                          linestyle='--', linewidth=1.5,
                          label=tp_target_label)
    axes[row, 0].set_title(f'{titles[svc]}\nThroughput')
    axes[row, 0].set_ylabel(tp_ylabel)
    axes[row, 0].set_xlabel('Transmission index')
    axes[row, 0].legend(fontsize=8)
    axes[row, 0].grid(True, alpha=0.3)

    # Plot 2 — Jitter per transmission
    axes[row, 1].plot(jit, color=c, linewidth=0.8,
                      alpha=0.7, label='Measured')
    if q['jitter']:
        axes[row, 1].axhline(y=q['jitter'], color='red',
                              linestyle='--', linewidth=1.5,
                              label=f"Deadline {q['jitter']}ms")
    axes[row, 1].set_title(f'{titles[svc]}\nJitter')
    axes[row, 1].set_ylabel('Jitter (ms)')
    axes[row, 1].set_xlabel('Transmission index')
    axes[row, 1].legend(fontsize=8)
    axes[row, 1].grid(True, alpha=0.3)
    axes[row, 1].set_ylim([0, 40])    

    # Plot 3 — Mean throughput per run
    run_means = []
    for run in range(1, 6):
        if run in all_data[svc]:
            tp_run, _, _ = extract(all_data[svc][run])
            val = np.mean(tp_run)/1000 if svc == 'embb' \
                  else np.mean(tp_run)
            run_means.append(val)
        else:
            run_means.append(0)

    axes[row, 2].bar(range(1, 6), run_means,
                     color=c, alpha=0.7)
    axes[row, 2].axhline(y=tp_target_plot, color='red',
                          linestyle='--', linewidth=1.5,
                          label=tp_target_label)
    axes[row, 2].set_title(
        f'{titles[svc]}\nMean Throughput per Run')
    axes[row, 2].set_ylabel(tp_ylabel)
    axes[row, 2].set_xlabel('Run number')
    axes[row, 2].set_xticks(range(1, 6))
    axes[row, 2].legend(fontsize=8)
    axes[row, 2].grid(True, alpha=0.3)

plt.tight_layout()
plot_path = os.path.join(OUT,
    'exp3_results_1.png')
plt.savefig(plot_path, dpi=150, bbox_inches='tight')
print(f"\nPlot saved: {plot_path}")
