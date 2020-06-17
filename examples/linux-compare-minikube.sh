#!/bin/bash
#
# Gather data comparing the overhead of multiple local Kubernetes 
readonly TESTS=$1

# How many iterations to cycle through
readonly TEST_ITERATIONS=3

# How long to poll CPU usage for (each point is an average over this period)
readonly POLL_DURATION=5s

# How long to measure background usage for. 5 minutes too short, 10 minutes too long
readonly TOTAL_DURATION=7m

# How all tests will be identified
readonly SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$"

measure() {
  local name=$1
  local iteration=$2
  local filename="results/${SESSION_ID}/cstat.${name}.$$-${iteration}"

  echo ""
  echo "  >> Current top processes by CPU:"
  top -n 3 -l 2 -s 2 -o cpu  | tail -n4 | awk '{ print $1 " " $2 " " $3 " " $4 }'

  echo ""
  echo "  >> Measuring ${name} and saving to ${filename} ..."
  cstat --poll "${POLL_DURATION}" --for "${TOTAL_DURATION}" --busy --header=false | tee "${filename}"
}


cleanup() {
  echo "  >> Deleting local clusters ..."

  # workaround delete hang w/ docker driver: https://github.com/kubernetes/minikube/issues/7657
  minikube unpause 2>/dev/null >/dev/null

  minikube delete --all 2>/dev/null >/dev/null

  sleep 5
}




main() {
  echo "Session ID: ${SESSION_ID}"
  mkdir -p "results/${SESSION_ID}"

  echo "----[ versions ]------------------------------------"
  minikube version || { echo "minikube version failed"; exit 1; }
  if [[ -x ./out/minikube ]]; then
    ./out/minikube version || { echo "./out/minikube version failed"; exit 1; }
  fi
  master.minikube version
  docker version
  echo "----------------------------------------------------"
  echo ""

  for i in $(seq 1 ${TEST_ITERATIONS}); do
    echo ""
    echo "==> session ${SESSION_ID}, iteration $i"
    cleanup


    # Measure the background noise on this system
    sleep 15
    measure idle $i

    echo ""


    # Sleep because we are too lazy to detect when Docker is up
    sleep 45
    # Run cleanup once more now that Docker is online
    cleanup


    #  hyperkit virtualbox vmware
    for driver in  docker kvm2; do

      echo ""
      echo "-> minikube --driver=${driver}"
      time minikube start --driver "${driver}" && measure "minikube.${driver}" $i
      # minikube pause && measure "minikube_paused.${driver}" $i
      cleanup

      if [[ -x "./out/minikube" ]]; then
        echo "-> ./out/minikube --driver=${driver}"
        time ./out/minikube start --driver "${driver}" && measure "out.minikube.${driver}" $i
        # minikube pause && measure "out.minikube_paused.${driver}" $i
        cleanup
      fi

      echo ""
      echo "-> master.minikube --driver=${driver}"
      time master.minikube start --driver "${driver}" && measure "master.minikube.${driver}" $i
      # minikube pause && measure "minikube_paused.${driver}" $i
      cleanup

      if [[ -x "./out/master.minikube" ]]; then
        echo "-> ./out/master.minikube --driver=${driver}"
        time ./out/master.minikube start --driver "${driver}" && measure "out.master.minikube.${driver}" $i
        # minikube pause && measure "out.minikube_paused.${driver}" $i
        cleanup
      fi

    done ## driver
  done ## iteration
}

main "$@"
