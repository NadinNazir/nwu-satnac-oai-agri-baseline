#!/bin/bash
# Experiment 1 — urllc Isolated Baseline
# 10 runs, 20 transmissions per run
# Output: ~/iperf_results/testbed/exp1/urllc/



LOG=~/iperf_results/testbed/exp1/urllc/urllc_exp1_log.txt

UE_IP=$(docker exec oai-nr-ue2 bash -c \
        "ip addr show oaitun_ue1 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")
echo "UE2 tunnel IP: ${UE_IP}" | tee -a $LOG

echo "================================================" | tee -a $LOG
echo "EXPERIMENT 1 — urllc ISOLATED BASELINE" | tee -a $LOG
echo "Date: $(date)" | tee -a $LOG
echo "UE: oai-nr-ue2 (IMSI: 001010000000102)" | tee -a $LOG
echo "Service: urllc — C2 link simulation" | tee -a $LOG
echo "Rate: 28 kbps | Packet: 256B | Period: 6s" | tee -a $LOG
echo "Runs: 10 | Transmissions per run: 20" | tee -a $LOG
echo "================================================" | tee -a $LOG

for run in $(seq 1 10); do
    echo "" | tee -a $LOG
    echo "--- RUN $run of 10 ---" | tee -a $LOG
    echo "Start: $(date +%H:%M:%S)" | tee -a $LOG

    # Start server
    docker exec -d oai-ext-dn iperf3 -s -p 5202
    sleep 5
    docker exec oai-nr-ue2 timeout 130 ping -I oaitun_ue1 -i 0.2 -D 192.168.70.135 \
       |head -c 50M > ~/iperf_results/testbed/exp1/urllc/urllc_run_${run}_ping.log 2>&1 &
    PING_PID=$!
    echo "Ping started (PID $PING_PID)" | tee -a $LOG
    
    
    # Run 20 transmissions
    for i in $(seq 1 20); do
        docker exec oai-nr-ue2 bash -c \
            "iperf3 -c 192.168.70.135 -p 5202 \
            -B ${UE_IP} -u -b 28K -l 256 -t 1 -J" \
            >> ~/iperf_results/testbed/exp1/urllc/urllc_run_${run}.json
        echo "  TX $i/20 at $(date +%H:%M:%S)" | tee -a $LOG
        sleep 5
    done
    
    kill $PING_PID 2>/dev/null
    wait $PING_PID 2>/dev/null
    echo "Ping stopped" | tee -a $LOG

    echo "End: $(date +%H:%M:%S)" | tee -a $LOG
    echo "Output: urllc_run_${run}.json" | tee -a $LOG

    # Stop iperf3
    docker exec oai-ext-dn bash -c "pkill iperf3"
    docker exec oai-nr-ue2 bash -c "pkill iperf3" 2>/dev/null
    echo "iperf3 stopped" | tee -a $LOG

    # Kill UE
    docker compose -f docker-compose-ran.yml down -t2 oai-nr-ue2
    echo "UE stopped" | tee -a $LOG

    # Reset sqn
    docker exec -it mysql mysql -u test -ptest oai_db -e "
    UPDATE AuthenticationSubscription
    SET sequenceNumber = '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}'
    WHERE ueid = '001010000000102';" 2>/dev/null
    echo "sqn reset complete" | tee -a $LOG

    # Restart UE
    docker compose -f docker-compose-ran.yml up -d oai-nr-ue2
    echo "UE restarting..." | tee -a $LOG

    # Wait for UE to attach
    sleep 20
    
    UE_IP=$(docker exec oai-nr-ue2 bash -c \
        "ip addr show oaitun_ue1 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")
    echo "UE2 tunnel IP: ${UE_IP}" | tee -a $LOG


    # Verify UE attached
    if [ -n "$UE_IP" ]; then
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
echo "EXPERIMENT 1 urllc COMPLETE" | tee -a $LOG
echo "Finished: $(date)" | tee -a $LOG
echo "Results: ~/iperf_results/testbed/exp1/urllc/" | tee -a $LOG
echo "================================================" | tee -a $LOG
 kill $PING_PID 2>/dev/null

    AVAIL=$(df / --output=avail | tail -1)
    if [ "$AVAIL" -lt 5000000 ]; then
        echo "WARNING: Low disk space (${AVAIL} KB) — aborting experiment" | tee -a $LOG
        exit 1
    fi
