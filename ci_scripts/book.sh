#!/bin/bash
NUMBEROFCOMMITS=$(git log --all --oneline | wc -l)
while :
  WHICHCOMMIT=$(( ( RANDOM % ${NUMBEROFCOMMITS} )  + 1 ))
  COMMITSUBJECT=$(git log --oneline --all -${WHICHCOMMIT} | tail -n1)
  COMMITSUBJECT_=$(echo $COMMITSUBJECT | cut -b0-60)
do
  if [ $RANDOM -lt 14000 ]; then 
    printf "\e[1m%-60s \e[32m%-10s\e[m\n" "${COMMITSUBJECT_}"  ' PASSED'
  elif [ $RANDOM -gt 15000 ]; then  
    printf "\e[1m%-60s \e[31m%-10s\e[m\n" "${COMMITSUBJECT_}"  ' FAILED'
  fi  
Done
