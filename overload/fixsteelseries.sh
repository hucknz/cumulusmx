#!/bin/bash
file_name=gauges.js
directory=/opt/CumulusMX/web/lib/steelseries/scripts/
cd ${directory}
while :; do
        if [[ -f ${file_name} ]]; then
                cp gauges.js gauges.bak
                sed -i 's/digitalFont        : false,/digitalFont        : true,/g' ${file_name}
                sed -i 's/digitalForecast    : false,/digitalForecast    : true,/g' ${file_name}
                sed -i 's/pageUpdateLimit    : 20,/pageUpdateLimit    : 0,/g' ${file_name}
            exit 0
        fi
        sleep 5s
done
