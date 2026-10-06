#!/bin/bash
# Experiment 1 — mMTC Isolated Baseline
# 10 runs, 20 transmissions per run
# Output: ~/iperf_results/testbed/exp1/mmtc/



LOG=~/iperf_results/testbed/exp1/mmtc/mmtc_exp1_log.txt

echo "================================================" | tee -a $LOG
echo "EXPERIMENT 1 — mMTC ISOLATED BASELINE" | tee -a $LOG
echo "Date: $(date)" | tee -a $LOG
echo "UE: oai-nr-ue1 (IMSI: 001010000000101)" | tee -a $LOG
echo "Service: mMTC — Soil sensor simulation" | tee -a $LOG
echo "Rate: 1 kbps | Packet: 64B | Period: 6s" | tee -a $LOG
echo "Runs: 10 | Transmissions per run: 20" | tee -a $LOG
echo "================================================" | tee -a $LOG

for run in $(seq 1 10); do
    echo "" | tee -a $LOG
    echo "--- RUN $run of 10 ---" | tee -a $LOG
    echo "Start: $(date +%H:%M:%S)" | tee -a $LOG

    # Start server
    docker exec -d oai-ext-dn iperf3 -s -p 5201
    sleep 1

    # Run 20 transmissions
    for i in $(seq 1 20); do
        docker exec oai-nr-ue1 bash -c \
            "iperf3 -c 192.168.70.135 -p 5201 \
            -B 10.0.0.2 -u -b 1K -l 64 -t 1 -J" \
            >> ~/iperf_results/testbed/exp1/mmtc/mmtc_run_${run}.json
        echo "  TX $i/20 at $(date +%H:%M:%S)" | tee -a $LOG
        sleep 5
    done

    echo "End: $(date +%H:%M:%S)" | tee -a $LOG
    echo "Output: mmtc_run_${run}.json" | tee -a $LOG

    # Stop iperf3
    docker exec oai-ext-dn bash -c "pkill iperf3"
    docker exec oai-nr-ue1 bash -c "pkill iperf3" 2>/dev/null
    echo "iperf3 stopped" | tee -a $LOG

    # Kill UE
    docker compose -f ~/oai-workshops/cn/docker-compose-ran.yml \
        stop oai-nr-ue1
    echo "UE stopped" | tee -a $LOG

    # Reset sqn
    docker exec -it mysql mysql -u test -ptest oai_db -e "
    UPDATE AuthenticationSubscription
    SET sequenceNumber = '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}'
    WHERE ueid = '001010000000101';" 2>/dev/null
    echo "sqn reset complete" | tee -a $LOG

    # Restart UE
    docker compose -f ~/oai-workshops/cn/docker-compose-ran.yml \
        up -d oai-nr-ue1
    echo "UE restarting..." | tee -a $LOG

    # Wait for UE to attach
    sleep 20

    # Verify UE attached
    ATTACHED=$(docker exec oai-nr-ue1 bash -c \
        "ip addr show oaitun_ue1 2>/dev/null | grep inet | wc -l")
    if [ "$ATTACHED" -gt 0 ]; then
        echo "UE attached successfully" | tee -a $LOG
    else
        echo "WARNING: UE not attached — waiting 10s more" | tee -a $LOG
        sleep 10
    fi

    # Gap between runs
    echo "Waiting 10s before next run..." | tee -a $LOG
    sleep 10
done

echo "" | tee -a $LOG
echo "================================================" | tee -a $LOG
echo "EXPERIMENT 1 mMTC COMPLETE" | tee -a $LOG
echo "Finished: $(date)" | tee -a $LOG
echo "Results: ~/iperf_results/testbed/exp1/mmtc/" | tee -a $LOG
echo "================================================" | tee -a $LOG
