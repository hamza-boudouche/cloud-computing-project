#!/bin/bash

no_of_requests=1000

#parsing params
if [ $# -lt 1 ]
  then
      echo "Not enough arguments, you must give at least the url and optionally \
          the number of requests to send (in this order)"
    exit 1
fi

url=$1

if [ -z "$2" ]
  then
      echo "argument for number of requests not passed, defaulting to $no_of_requests"
  else
      no_of_requests=$2
      echo "configured to send $no_of_requests requests"
fi

#counting responses
v1=0
v2=0

for ((i = 0; i < no_of_requests; i++)); do
    result=$(curl -s $url)
    echo $i
    if [ $(echo $result | grep SunglassesV2 | wc -l) -eq 1 ]
    then
        ((v2+=1))
    elif [ $(echo $result | grep Sunglasses | wc -l) -eq 1 ]
    then
        ((v1+=1))
    fi
done

#showing response counts
echo v1 = $(bc <<< "scale=2; $v1*100/$no_of_requests") %
echo v2 = $(bc <<< "scale=2; $v2*100/$no_of_requests") %
