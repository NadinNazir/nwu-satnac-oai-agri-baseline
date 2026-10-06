#!/bin/bash
# Experiment 2 — mMTC+ EMBB
# 5 runs, 20 + 5 transmissions per run
# Output: ~/iperf_results/testbed/exp2/mmtc_embb/

LOG=~/iperf_results/testbed/exp2/mmtc_embb/mmtc_embb_log.txt
    
docker compose -f docker-compose-ran.yml up -d oai-nr-ue1 
    sleep 10
docker compose -f docker-compose-ran.yml up -d oai-nr-ue3
    echo "UEs Starting..." | tee -a $LOG
    sleep 10
    
MMTC_IP=$(docker exec oai-nr-ue1 bash -c \
            "ip addr show oaitun_ue1 2>/dev/null | \
             grep 'inet ' | awk '{print \$2}' | \
             cut -d/ -f1")
EMBB_IP=$(docker exec oai-nr-ue3 bash -c \
            "ip addr show oaitun_ue1 2>/dev/null | \
             grep 'inet ' | awk '{print \$2}' | \
             cut -d/ -f1")

echo "================================================" | tee -a $LOG
echo "EXPERIMENT 2 — mMTC+ embb" | tee -a $LOG
echo "Date: $(date)" | tee -a $LOG
echo "UEs: oai-nr-ue1 (IMSI: 001010000000101) & oai-nr-ue3 (IMSI: 001010000000103)" | tee -a $LOG
echo "================================================" | tee -a $LOG

for run in $(seq 1 5); do
    echo "" | tee -a $LOG
    echo "--- RUN $run of 5 ---" | tee -a $LOG
    echo "Start: $(date +%H:%M:%S)" | tee -a $LOG

    # Start server
    docker exec -d oai-ext-dn iperf3 -s -p 5201
    docker exec -d oai-ext-dn iperf3 -s -p 5203
    sleep 1

   (
    	for i in $(seq 1 20); do
        	docker exec oai-nr-ue1 iperf3 -c 192.168.70.135 -p 5201 \
            	-B "$MMTC_IP" -u -b 1K -l 64 -t 1 -J \
            	>> ~/iperf_results/testbed/exp2/mmtc_embb/mmtc_run_${run}.json
        	echo "mMTC TX $i/20 at $(date +%H:%M:%S)" | tee -a "$LOG"
        	sleep 6
    	done
   ) &
   (
   	for j in $(seq 1 5); do
        	docker exec oai-nr-ue3 iperf3 -c 192.168.70.135 -p 5203 \
            	-B "$EMBB_IP" -u -b 120M -t 15 -J \
            	>> ~/iperf_results/testbed/exp2/mmtc_embb/embb_run_${run}.json
        	echo "eMBB TX $j/5 at $(date +%H:%M:%S)" | tee -a "$LOG"
        	sleep 9
    	done
   ) &

        wait  
    echo "End: $(date +%H:%M:%S)" | tee -a $LOG
    echo "All 20 mMTC and 5 eMBB transmissions completed for Run ${run}." | tee -a "$LOG"
    

    # Stop iperf3
    docker exec oai-ext-dn bash -c "pkill iperf3" 2>/dev/null
    docker exec oai-nr-ue1 bash -c "pkill iperf3" 2>/dev/null
    docker exec oai-nr-UE3 bash -c "pkill iperf3" 2>/dev/null
    echo "iperf3 stopped" | tee -a $LOG
    
    
    # Kill UE
    docker compose -f ~/oai-workshops/cn/docker-compose-ran.yml \
        down -t2 oai-nr-ue1
    docker compose -f ~/oai-workshops/cn/docker-compose-ran.yml \
        down -t2 oai-nr-ue3    
    echo "UEs stopped" | tee -a $LOG

    # Reset sqn
    docker exec -it mysql mysql -u test -ptest oai_db -e "
    UPDATE AuthenticationSubscription
    SET sequenceNumber = '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}'
    WHERE ueid = '001010000000101';" 2>/dev/null &
    docker exec -it mysql mysql -u test -ptest oai_db -e "
    UPDATE AuthenticationSubscription
    SET sequenceNumber = '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}'
    WHERE ueid = '001010000000103';" 2>/dev/null
    echo "sqn reset complete" | tee -a $LOG

    # Restart UE
    docker compose -f docker-compose-ran.yml up -d oai-nr-ue1 
    sleep 10
    docker compose -f docker-compose-ran.yml up -d oai-nr-ue3
    echo "UEs restarting..." | tee -a $LOG

    # Wait for UE to attach
    sleep 20


   # Get updated IPs
    MMTC_IP=$(docker exec oai-nr-ue1 bash -c \
        "ip addr show oaitun_ue1 2>/dev/null | \
         grep 'inet ' | awk '{print \$2}' | \
         cut -d/ -f1")
    EMBB_IP=$(docker exec oai-nr-ue3 bash -c \
        "ip addr show oaitun_ue1 2>/dev/null | \
         grep 'inet ' | awk '{print \$2}' | \
         cut -d/ -f1")

    # Verify attachment
    if [ -n "$MMTC_IP" ] && [ -n "$EMBB_IP" ]; then
        echo "UEs attached — mMTC:$MMTC_IP EMBB:$EMBB_IP" \
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
        EMBB_IP=$(docker exec oai-nr-ue3 bash -c \
            "ip addr show oaitun_ue1 2>/dev/null | \
             grep 'inet ' | awk '{print \$2}' | \
             cut -d/ -f1")
        echo "Retry — mMTC:$MMTC_IP EMBB:$EMBB_IP" \
            | tee -a $LOG
    fi

    echo "Waiting 10s before next run..." | tee -a $LOG
    sleep 10
done


echo "================================================" | tee -a $LOG
echo "EXPERIMENT 2 — mMTC+ EMBB" | tee -a $LOG
echo "Finished: $(date)" | tee -a $LOG
echo "Results: ~/iperf_results/testbed/exp2/mmtc_embb/" | tee -a $LOG
echo "================================================" | tee -a $LOG
    # Stop iperf3
    docker exec oai-ext-dn bash -c "pkill iperf3" 2>/dev/null
    docker exec oai-nr-ue1 bash -c "pkill iperf3" 2>/dev/null
    docker exec oai-nr-UE3 bash -c "pkill iperf3" 2>/dev/null
    echo "iperf3 stopped" | tee -a $LOG
    

