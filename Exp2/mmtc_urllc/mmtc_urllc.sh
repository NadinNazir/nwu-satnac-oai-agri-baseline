#!/bin/bash
# Experiment 2 — mMTC+ URLLC
# 5 runs, 20 + 20 transmissions per run
# Output: ~/iperf_results/testbed/exp2/mmtc_urllc/

LOG=~/iperf_results/testbed/exp2/mmtc_urllc/mmtc_urllc_log.txt

MMTC_IP=$(docker exec oai-nr-ue1 bash -c \
            "ip addr show oaitun_ue1 2>/dev/null | \
             grep 'inet ' | awk '{print \$2}' | \
             cut -d/ -f1")
URLLC_IP=$(docker exec oai-nr-ue2 bash -c \
            "ip addr show oaitun_ue1 2>/dev/null | \
             grep 'inet ' | awk '{print \$2}' | \
             cut -d/ -f1")

echo "================================================" | tee -a $LOG
echo "EXPERIMENT 2 — mMTC+ URLLC" | tee -a $LOG
echo "Date: $(date)" | tee -a $LOG
echo "UEs: oai-nr-ue1 (IMSI: 001010000000101) & oai-nr-ue2 (IMSI: 001010000000102)" | tee -a $LOG
echo "================================================" | tee -a $LOG

for run in $(seq 1 5); do
    echo "" | tee -a $LOG
    echo "--- RUN $run of 5 ---" | tee -a $LOG
    echo "Start: $(date +%H:%M:%S)" | tee -a $LOG

    # Start server
    docker exec -d oai-ext-dn iperf3 -s -p 5201
    docker exec -d oai-ext-dn iperf3 -s -p 5202
    sleep 1

    # Start pings (one per UE, run concurrently with the transmissions)
    docker exec oai-nr-ue1 timeout 130 ping -I oaitun_ue1 -i 0.2 -D 192.168.70.135 \
        | head -c 50M > ~/iperf_results/testbed/exp2/mmtc_urllc/mmtc_run_${run}_ping.log 2>&1 &
    MMTC_PING_PID=$!
    docker exec oai-nr-ue2 timeout 130 ping -I oaitun_ue1 -i 0.2 -D 192.168.70.135 \
        | head -c 50M > ~/iperf_results/testbed/exp2/mmtc_urllc/urllc_run_${run}_ping.log 2>&1 &
    URLLC_PING_PID=$!
    echo "Pings started (mMTC PID $MMTC_PING_PID, URLLC PID $URLLC_PING_PID)" | tee -a $LOG

    # Run 20 transmissions
    for i in $(seq 1 20); do
        (
          docker exec oai-nr-ue1 bash -c \
              "iperf3 -c 192.168.70.135 -p 5201 \
              -B $MMTC_IP -u -b 1K -l 64 -t 1 -J" \
              >> ~/iperf_results/testbed/exp2/mmtc_urllc/mmtc_run_${run}.json
        ) &
        
        (  
          docker exec oai-nr-ue2 bash -c \
              "iperf3 -c 192.168.70.135 -p 5202 \
              -B $URLLC_IP -u -b 28K -l 256 -t 1 -J" \
              >> ~/iperf_results/testbed/exp2/mmtc_urllc/urllc_run_${run}.json
        ) & 
        wait  
        echo "  TX $i/20 at $(date +%H:%M:%S)" | tee -a $LOG
        sleep 5
    done

    echo "End: $(date +%H:%M:%S)" | tee -a $LOG
    echo "Output: mmtc_run_${run}.json && urllc_run_${run}.json" | tee -a $LOG

    # Stop pings
    kill $MMTC_PING_PID $URLLC_PING_PID 2>/dev/null
    wait $MMTC_PING_PID $URLLC_PING_PID 2>/dev/null
    echo "Pings stopped" | tee -a $LOG

    # Stop iperf3
    docker exec oai-ext-dn bash -c "pkill iperf3" 2>/dev/null
    docker exec oai-nr-ue1 bash -c "pkill iperf3" 2>/dev/null
    docker exec oai-nr-ue2 bash -c "pkill iperf3" 2>/dev/null
    echo "iperf3 stopped" | tee -a $LOG
    
    
    # Kill UE
    docker compose -f ~/oai-workshops/cn/docker-compose-ran.yml \
        down -t2 oai-nr-ue1
    docker compose -f ~/oai-workshops/cn/docker-compose-ran.yml \
        down -t2 oai-nr-ue2    
    echo "UEs stopped" | tee -a $LOG

    # Reset sqn
    docker exec -it mysql mysql -u test -ptest oai_db -e "
    UPDATE AuthenticationSubscription
    SET sequenceNumber = '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}'
    WHERE ueid = '001010000000101';" 2>/dev/null &
    docker exec -it mysql mysql -u test -ptest oai_db -e "
    UPDATE AuthenticationSubscription
    SET sequenceNumber = '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}'
    WHERE ueid = '001010000000102';" 2>/dev/null
    echo "sqn reset complete" | tee -a $LOG

    # Restart UE
    docker compose -f docker-compose-ran.yml up -d oai-nr-ue1 
    sleep 10
    docker compose -f docker-compose-ran.yml up -d oai-nr-ue2
    echo "UEs restarting..." | tee -a $LOG

    # Wait for UE to attach
    sleep 20


   # Get updated IPs
    MMTC_IP=$(docker exec oai-nr-ue1 bash -c \
        "ip addr show oaitun_ue1 2>/dev/null | \
         grep 'inet ' | awk '{print \$2}' | \
         cut -d/ -f1")
    URLLC_IP=$(docker exec oai-nr-ue2 bash -c \
        "ip addr show oaitun_ue1 2>/dev/null | \
         grep 'inet ' | awk '{print \$2}' | \
         cut -d/ -f1")

    # Verify attachment
    if [ -n "$MMTC_IP" ] && [ -n "$URLLC_IP" ]; then
        echo "UEs attached — mMTC:$MMTC_IP URLLC:$URLLC_IP" \
            | tee -a $LOG
    else
        echo "WARNING: UE not attached — waiting 15s more" \
            | tee -a $LOG
        sleep 15
        # Try again
        MMTC_IP=$(docker exec oai-nr-ue1 bash -c \
            "ip addr show oaitun_ue1 2>/dev/null | \
             grep 'inet ' | awk '{print \$2}' | \
             cut -d/ -f1")
        URLLC_IP=$(docker exec oai-nr-ue2 bash -c \
            "ip addr show oaitun_ue1 2>/dev/null | \
             grep 'inet ' | awk '{print \$2}' | \
             cut -d/ -f1")
        echo "Retry — mMTC:$MMTC_IP URLLC:$URLLC_IP" \
            | tee -a $LOG
    fi

    echo "Waiting 10s before next run..." | tee -a $LOG
    sleep 10
done


echo "================================================" | tee -a $LOG
echo "EXPERIMENT 2 — mMTC+ URLLC" | tee -a $LOG
echo "Finished: $(date)" | tee -a $LOG
echo "Results: ~/iperf_results/testbed/exp2/mmtc_urllc/" | tee -a $LOG
echo "================================================" | tee -a $LOG

    # Stop pings
    kill $MMTC_PING_PID $URLLC_PING_PID 2>/dev/null
    wait $MMTC_PING_PID $URLLC_PING_PID 2>/dev/null
    echo "Pings stopped" | tee -a $LOG
