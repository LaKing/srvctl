#!/bin/bash
## @@@ harness-pick [OPTION]
## @en Pick an option (dynamic-help fixture).
## &&& echo alpha beta gamma
## &en Options are shown dynamically in brackets by the hint path.
[[ $SRVCTL ]] || exit 10

echo "$ARG"
