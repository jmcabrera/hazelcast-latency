#!/usr/bin/env bash

function log {
    echo $(date +"%Y/%m/%d %X") $@
}

### for Hazelcast 2

function split {
    log "splitting"
    sudo iptables -t filter -I ISOLATION 1 -s 127.1.0.0/16 -d 127.2.0.0/16 -j DROP
    sudo iptables -t filter -I ISOLATION 1 -s 127.2.0.0/16 -d 127.1.0.0/16 -j DROP
    state2["intersite"]="shut down"
    [[ "$1" =~ ^[1-9][0-9]*$ ]] && sleep $1 && unsplit
}

function unsplit {
    log "unsplitting"
    sudo iptables -t filter -D ISOLATION -s 127.1.0.0/16 -d 127.2.0.0/16 -j DROP
    sudo iptables -t filter -D ISOLATION -s 127.2.0.0/16 -d 127.1.0.0/16 -j DROP
    state2["intersite"]="opened"
}

function unreliable {
    sa=${1:-"10"}
    sb=${2:-"10"}
    ua=${3:-$sa}
    ub=${4:-$sb}
    log "split $sa to $(($sa+$sb)) seconds then unsplit during $ua to $(($ua+$ub))"
    log "^C to stop please"
    bash -c 'while true; do split $(('$sa' + ($RANDOM % '$sb'))); sleep $(('$ua' + ($RANDOM % '$ub'))); done' | tee -a splitting.log
}

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
        sudo iptables -t filter -I ISOLATION 1 -d ${ip2[$i]} -j DROP
        sudo iptables -t filter -I ISOLATION 1 -s ${ip2[$i]} -j DROP
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
        sudo iptables -t filter -I ISOLATION 1 -d ${ip3[$i]} -j DROP
        sudo iptables -t filter -I ISOLATION 1 -s ${ip3[$i]} -j DROP
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

function setup {
    unset ip2 ip3 state2 state3
    
    # 127.0.0.0/24 : Application on site 1
    # 127.1.N.0/24 : Hazelcast N on site 1
    # 127.2.N.0/24 : Hazelcast N on site 2
    ip2=([0]=127.0.0.1 [1]=127.1.2.1 [2]=127.1.2.2 [3]=127.2.2.1 [4]=127.2.2.2)
    ip3=([0]=127.0.0.1 [1]=127.1.3.1 [2]=127.1.3.2 [3]=127.2.3.1 [4]=127.2.3.2)
    for i in "${!ip2[@]}"; do state2[$i]="opened" ; done
    for i in "${!ip3[@]}"; do state3[$i]="opened" ; done
    state2["intersite"]="opened"
    state3["intersite"]="opened"

    # packet size for loopback interface similar to a regular eth interface
    sudo ifconfig lo mtu 1500 up

    # Attach some IPs to lo
    for i in "${!ip2[@]}"; do sudo ifconfig lo add ${ip2[$i]}; done
    for i in "${!ip3[@]}"; do sudo ifconfig lo add ${ip3[$i]}; done

    # https://www.linux.com/tutorials/tc-show-manipulate-traffic-control-settings/
    # Make traffic between 127.x.2.0/24 and the rest 9 (+/- 1ms) slower
    sudo tc qdisc del dev lo root
    sudo tc qdisc add dev lo root handle 1: htb
    sudo tc class add dev lo parent 1: classid 1:1 htb rate 2gbit # site 1 : flux cluster <-> cluster et client <-> cluster
    sudo tc class add dev lo parent 1: classid 1:2 htb rate 2gbit # site 2 : flux cluster <-> cluster
    sudo tc class add dev lo parent 1: classid 1:3 htb rate 20mbit # site 2 : flux cluster <-> cluster

    # intra site 1
    sudo tc filter add dev lo protocol ip parent 1:0 prio 1 u32 match ip dst 127.1.0.0/16 match ip src 127.1.0.0/16 flowid 1:1 # flux site 1 <-> site 1
    sudo tc filter add dev lo protocol ip parent 1:0 prio 1 u32 match ip dst 127.1.0.0/16 match ip src 127.0.0.0/16 flowid 1:1 # flux site 1  -> client
    sudo tc filter add dev lo protocol ip parent 1:0 prio 1 u32 match ip dst 127.0.0.0/16 match ip src 127.1.0.0/16 flowid 1:1 # flux client  -> site 1

    # intra site 2
    sudo tc filter add dev lo protocol ip parent 1:0 prio 1 u32 match ip dst 127.2.0.0/16 match ip src 127.2.0.0/16 flowid 1:2 # flux site 2 <-> site 2

    # intersite
    sudo tc filter add dev lo protocol ip parent 1:0 prio 1 u32 match ip dst 127.1.0.0/16 match ip src 127.2.0.0/16 flowid 1:3 # flux site 1 -> site 2
    sudo tc filter add dev lo protocol ip parent 1:0 prio 1 u32 match ip dst 127.2.0.0/16 match ip src 127.1.0.0/16 flowid 1:3 # flux site 2 -> site 1
    sudo tc filter add dev lo protocol ip parent 1:0 prio 1 u32 match ip dst 127.0.0.0/16 match ip src 127.2.0.0/16 flowid 1:3 # flux client -> site 2
    sudo tc filter add dev lo protocol ip parent 1:0 prio 1 u32 match ip dst 127.2.0.0/16 match ip src 127.0.0.0/16 flowid 1:3 # flux site 2 -> client

    sudo tc qdisc add dev lo parent 1:3 handle 30: netem delay 5ms 1ms 5% loss random 5% # Ajout d'un délai sur le flow 1:3 qui correspond à l'intersite.

    # ISOLATION will host failures.
    sudo iptables -t filter -N ISOLATION
    sudo iptables -t filter -A INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j ISOLATION
    sudo iptables -t filter -A OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j ISOLATION

    # MULTISITE creates the expected topography
    sudo iptables -t filter -N MULTISITE
    sudo iptables -t filter -A INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j MULTISITE
    sudo iptables -t filter -A OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j MULTISITE
    sudo iptables -t filter -A MULTISITE -s 127.0.0.0/16 -d 127.0.0.0/16 -j RETURN # Let "normal" localhost traffic be.
    sudo iptables -t filter -A MULTISITE -s 127.0.0.0/16 -d 127.1.0.0/16 -j RETURN # Client can find site 1 (hzct 2 and 3)
    sudo iptables -t filter -A MULTISITE -s 127.1.0.0/16 -d 127.0.0.0/16 -j RETURN
    sudo iptables -t filter -A MULTISITE -s 127.1.2.0/24 -d 127.1.2.0/24 -j RETURN # Hzct 2 cluster can discuss freely on site 1
    sudo iptables -t filter -A MULTISITE -s 127.2.2.0/24 -d 127.2.2.0/24 -j RETURN # ......................................... 2
    sudo iptables -t filter -A MULTISITE -s 127.1.2.0/24 -d 127.2.2.0/24 -j RETURN # ................................. site 1 -> site 2
    sudo iptables -t filter -A MULTISITE -s 127.2.2.0/24 -d 127.1.2.0/24 -j RETURN # ................................. site 2 -> site 1
    sudo iptables -t filter -A MULTISITE -s 127.1.3.0/24 -d 127.1.3.0/24 -j RETURN # Hzct 3 cluster can discuss freely on site 1
    sudo iptables -t filter -A MULTISITE -s 127.2.3.0/24 -d 127.2.3.0/24 -j RETURN # ......................................... 2
    sudo iptables -t filter -A MULTISITE -s 127.1.3.0/24 -d 127.2.3.0/24 -j RETURN # ................................. site 1 -> site 2
    sudo iptables -t filter -A MULTISITE -s 127.2.3.0/24 -d 127.1.3.0/24 -j RETURN # ................................. site 2 -> site 1


    sudo iptables -t filter -A MULTISITE -j DROP # baseline

    # MONITOR will allow us to see the actual flow of packets (iptables -L MONITOR n -v).
    sudo iptables -t filter -N MONITOR
    sudo iptables -t filter -A INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j MONITOR
    sudo iptables -t filter -A OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j MONITOR

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
    sudo tc qdisc add dev lo root pfifo

    sudo iptables -t filter -D INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j MULTISITE
    sudo iptables -t filter -D INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j MONITOR
    sudo iptables -t filter -D INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j ISOLATION
    sudo iptables -t filter -D OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j MULTISITE
    sudo iptables -t filter -D OUTPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j MONITOR
    sudo iptables -t filter -D OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j ISOLATION

    sudo iptables -F MULTISITE
    sudo iptables -F ISOLATION
    sudo iptables -F MONITOR
    sudo iptables -X MULTISITE
    sudo iptables -X ISOLATION
    sudo iptables -X MONITOR

    for i in "${ip2[@]}"; do sudo ifconfig lo del $i; done
    for i in "${ip3[@]}"; do sudo ifconfig lo del $i; done

    sudo ifconfig lo mtu 65536 up
}

function monitor {
    sudo watch -d iptables -nvL MONITOR
}

function reset {
    sudo iptables -Z MONITOR
}

function compile {
    mvn clean package
}

function servers2 {
    nice -n 20 java -cp 2.5/target/2.5-1.0-SNAPSHOT-jar-with-dependencies.jar Server25 | tee server25-$(date +%Y%m%d-%H%M%S).log
}

function client2 {
    nice -n 20 java -cp 2.5/target/2.5-1.0-SNAPSHOT-jar-with-dependencies.jar Client25 | tee client25-$(date +%Y%m%d-%H%M%S).log
}

function servers3 {
    nice -n 20 java -cp 3.10/target/3.10-1.0-SNAPSHOT-jar-with-dependencies.jar Server310 | tee server310-$(date +%Y%m%d-%H%M%S).log
}

function client3 {
    nice -n 20 java -cp 3.10/target/3.10-1.0-SNAPSHOT-jar-with-dependencies.jar Client310 | tee client310-$(date +%Y%m%d-%H%M%S).log
}

export -f status2 shut2 open2 servers2 client2
export -f status3 shut3 open3 servers3 client3
export -f setup tear log compile monitor reset split unsplit unreliable

echo "#####################################################################"
echo "usage: ___>>> THIS SCRIPT MUST BE SOURCED, NOT EXECUTED <<<___"
echo ""
echo "command list:"
echo ""
echo "tear    : reopens everything. You need a call to setup"
echo "          to use shut and open again"
echo ""
echo "setup   : prepare a set of rules to make shut and open"
echo "          to work as expected"
echo ""
echo "split t : nodes 3 and 4 are unreachable for time t."
echo "          if t not given, split until 'unsplit' is called"
echo ""
echo "unsplit : undoes a split (but does not undo a shut)"
echo ""
echo "unreliable a b c d: start a loop where intersite is split during a and (a+b)"
echo "                    seconds they unsplit during c and (c+d) seconds"
echo "                    a,b defaults to 10; c defaults to a; d defaults to c"
echo ""
echo "monitor : Shows a list of traffic between every ips defined by this tool"
echo "          see servers2 and servers3 for a list."
echo ""
echo "servers2: starts 4 servers on Hazelcast 2.5 with ips 127.[1-2].2.[1-2]"
echo "          127.1._._ is site 1, 127.2._._ is site 2"
echo ""
echo "shut2 x : (x in 1..4) isolates node x"
echo ""
echo "open2 x : (x in 1..4) make nodes x reachable again, after they have"
echo "          sgut with the shut operation"
echo ""
echo "status2 : gives state of nodes and intersite"
echo ""
echo "client2 : gives state of nodes and intersite"
echo ""
echo "shut3, open3, servers3, client3 to act on the 127._.3._ nodes"
echo ""

sudo iptables -nvL MONITOR 1>/dev/null 2>&1 || setup