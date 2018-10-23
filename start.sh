#!/usr/bin/env bash

function log {
    echo $(date +"%x %X") $@
}

### for Hazelcast 2

function status2 {
    for i in "${!state2[@]}"
    do
        log "node $i    -> ${state2[$i]}"
    done
}

function shut2 {
    for i in "$@"
    do
        log "isolating node $i"
        sudo iptables -t filter -A ISOLATION -d ${ip2[$i]} -j DROP
        sudo iptables -t filter -A ISOLATION -s ${ip2[$i]} -j DROP
        state2[$i]="shut down"
    done
}

function open2 {
    for i in "$@"
    do
        log "making node $i reachable"
        sudo iptables -t filter -D ISOLATION -d ${ip2[$i]} -j DROP
        sudo iptables -t filter -D ISOLATION -s ${ip2[$i]} -j DROP
        state2[$i]="opened"
    done
}

function split2 {
    log "splitting"
    sudo iptables -t filter -A MULTISITE -s 127.2.1.0/24 -d 127.2.2.0/24 -j DROP
    sudo iptables -t filter -A MULTISITE -s 127.2.2.0/24 -d 127.2.1.0/24 -j DROP
    state2["intersite"]="shut down"
    [[ "$1" =~ ^[1-9][0-9]*$ ]] && sleep $1 && unsplit2
}

function unsplit2 {
    log "unsplitting"
    sudo iptables -t filter -D MULTISITE -s 127.2.1.0/24 -d 127.2.2.0/24 -j DROP
    sudo iptables -t filter -D MULTISITE -s 127.2.2.0/24 -d 127.2.1.0/24 -j DROP
    state2["intersite"]="opened"
}

function unreliable2 {
    log "^C to stop please"
    bash -c 'while true; do split2 $((2 + ($RANDOM % 5))); sleep $((2 + ($RANDOM % 5))); done'
    unsplit2
}

### for Hazelcast 3

function status3 {
    for i in "${!state3[@]}"
    do
        log "node $i    -> ${state3[$i]}"
    done
}

function shut3 {
    for i in "$@"
    do
        log "isolating node $i"
        sudo iptables -t filter -A ISOLATION -d ${ip3[$i]} -j DROP
        sudo iptables -t filter -A ISOLATION -s ${ip3[$i]} -j DROP
        state3[$i]="shut down"
    done
}

function open3 {
    for i in "$@"
    do
        log "making node $i reachable"
        sudo iptables -t filter -D ISOLATION -d ${ip3[$i]} -j DROP
        sudo iptables -t filter -D ISOLATION -s ${ip3[$i]} -j DROP
        state3[$i]="opened"
    done
}

function split3 {
    log "splitting"
    sudo iptables -t filter -A MULTISITE -s 127.3.1.0/24 -d 127.3.2.0/24 -j DROP
    sudo iptables -t filter -A MULTISITE -s 127.3.2.0/24 -d 127.3.1.0/24 -j DROP
    state3["intersite"]="shut down"
    [[ "$1" =~ ^[1-9][0-9]*$ ]] && sleep $1 && unsplit3
}

function unsplit3 {
    log "unsplitting"
    sudo iptables -t filter -D MULTISITE -s 127.3.1.0/24 -d 127.3.2.0/24 -j DROP
    sudo iptables -t filter -D MULTISITE -s 127.3.2.0/24 -d 127.3.1.0/24 -j DROP
    state3["intersite"]="opened"
}

function unreliable3 {
    log "^C to stop please"
    bash -c 'while true; do split3 $((1 + $RANDOM % 5)); sleep $((1 + $RANDOM % 5)); done'
    unsplit3
}

function setup {
    unset ip2 ip3 state2 state3

    # 127.x.0.0/24 : Application on site 1
    # 127.x.1.0/24 : Hazelcast on site 1
    # 127.x.2.0/24 : Hazelcast on site 2
    ip2=([0]=127.0.0.1 [1]=127.2.1.1 [2]=127.2.1.2 [3]=127.2.2.1 [4]=127.2.2.2)
    ip3=([0]=127.0.0.1 [1]=127.3.1.1 [2]=127.3.1.2 [3]=127.3.2.1 [4]=127.3.2.2)
    for i in "${!ip2[@]}"; do state2[$i]="opened" ; done
    for i in "${!ip3[@]}"; do state3[$i]="opened" ; done
    state2["intersite"]="opened"
    state3["intersite"]="opened"

    # Attach some IPs to lo
    for i in "${!ip2[@]}"; do sudo ifconfig lo add ${ip2[$i]}; done
    for i in "${!ip3[@]}"; do sudo ifconfig lo add ${ip3[$i]}; done


    # Make traffic between 127.x.2.0/24 and the rest 9 (+/- 1ms) slower
    sudo tc qdisc add dev lo root handle 1: prio
    sudo tc qdisc add dev lo parent 1:3 handle 30: netem delay 5ms # 1ms distribution normal
    sudo tc qdisc replace dev lo handle 1: root prio bands 3 priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    sudo tc filter add dev lo protocol ip parent 1:0 prio 3 u32 match ip dst 127.2.2.0/24 match ip src 127.2.1.0/24 flowid 1:3
    sudo tc filter add dev lo protocol ip parent 1:0 prio 3 u32 match ip dst 127.2.1.0/24 match ip src 127.2.2.0/24 flowid 1:3

    sudo tc filter add dev lo protocol ip parent 1:0 prio 3 u32 match ip dst 127.2.2.0/24 match ip src 127.0.0.0/24 flowid 1:3
    sudo tc filter add dev lo protocol ip parent 1:0 prio 3 u32 match ip dst 127.0.0.0/24 match ip src 127.2.2.0/24 flowid 1:3

    sudo tc filter add dev lo protocol ip parent 1:0 prio 3 u32 match ip dst 127.3.2.0/24 match ip src 127.3.1.0/24 flowid 1:3
    sudo tc filter add dev lo protocol ip parent 1:0 prio 3 u32 match ip dst 127.3.1.0/24 match ip src 127.3.2.0/24 flowid 1:3

    sudo tc filter add dev lo protocol ip parent 1:0 prio 3 u32 match ip dst 127.3.2.0/24 match ip src 127.0.0.0/24 flowid 1:3
    sudo tc filter add dev lo protocol ip parent 1:0 prio 3 u32 match ip dst 127.0.0.0/24 match ip src 127.3.2.0/24 flowid 1:3

    sudo iptables -t filter -N MULTISITE
    sudo iptables -t filter -A INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j MULTISITE
    sudo iptables -t filter -A OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j MULTISITE

    # Nothing goes from 127.2._._ to 127.3._._ => Hzct 2 and 3 are contained
    sudo iptables -t filter -A MULTISITE -s 127.2.0.0/16 -d 127.3.0.0/16 -j DROP
    sudo iptables -t filter -A MULTISITE -s 127.3.0.0/16 -d 127.2.0.0/16 -j DROP

    # Nothing goes from 127.x.0._/24 to 127.0.2._/24 => App cannot access site 2
    sudo iptables -t filter -A MULTISITE -s 127.0.0.0/24 -d 127.2.2.0/24 -j DROP
    sudo iptables -t filter -A MULTISITE -s 127.2.2.0/24 -d 127.0.0.0/24 -j DROP
    sudo iptables -t filter -A MULTISITE -s 127.0.0.0/24 -d 127.3.2.0/24 -j DROP
    sudo iptables -t filter -A MULTISITE -s 127.3.2.0/24 -d 127.0.0.0/24 -j DROP

    # ISOLATION will host failures.
    sudo iptables -t filter -N ISOLATION
    sudo iptables -t filter -A INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j ISOLATION
    sudo iptables -t filter -A OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j ISOLATION

    # ISOLATION will allow us to see the actual flow of packets (iptables -L MONITOR n -v).
    sudo iptables -t filter -N MONITOR
    sudo iptables -t filter -A INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j MONITOR

    for i in "${ip2[@]}"
    do
        for j in "${ip2[@]}"
        do
            [ $i != $j ] && sudo iptables -t filter -A MONITOR -s $i -d $j -j ACCEPT
        done
    done

    for i in "${ip3[@]}"
    do
        for j in "${ip3[@]}"
        do
            [ $i != $j ] && sudo iptables -t filter -A MONITOR -s $i -d $j -j ACCEPT
        done
    done

    sudo iptables -t filter -A MONITOR -j ACCEPT
}

function tear {
    sudo tc qdisc del dev lo root

    sudo iptables -t filter -F INPUT
    sudo iptables -t filter -F OUTPUT
    sudo iptables -F MULTISITE
    sudo iptables -F ISOLATION
    sudo iptables -F MONITOR
    sudo iptables -X MULTISITE
    sudo iptables -X ISOLATION
    sudo iptables -X MONITOR

    for i in "${ip2[@]}"; do sudo ifconfig lo del $i; done
    for i in "${ip3[@]}"; do sudo ifconfig lo del $i; done

}

export -f status2 shut2 open2 split2 unsplit2 unreliable2
export -f status3 shut3 open3 split3 unsplit3 unreliable3
export -f setup tear log

log "undoing previously setup things if any"
tear
log "setting up the new things"
setup

echo "#####################################################################"
echo "usage: "
echo "tear    : reopens everything. You need a call to setup"
echo "          to use shut and open again"
echo ""
echo "setup   : prepare a set of rules to make shut and open"
echo "          to work as expected"
echo ""
echo "shut3, open3, split3, unsplit3 act on the 127.3.x.x nodes"
echo "shut2, open2, split2, unsplit2 act on the 127.2.x.x nodes"
echo ""
echo "shut2 x : (x in 1..4) isolates node x"
echo ""
echo "open2 x : (x in 1..4) make nodes x reachable again, after they have"
echo "          sgut with the shut operation"
echo ""
echo "split2 t: nodes 3 and 4 are unreachable for time t."
echo "          if t not given, split until 'unsplit' is called"
echo ""
echo "unsplit2: undoes a split (but does not undo a shut)"
echo ""
echo "status2 : gives state of nodes and intersite"
echo ""
echo "shut3, open3, split3, unsplit3 to act on the 127.3.x.x nodes"
