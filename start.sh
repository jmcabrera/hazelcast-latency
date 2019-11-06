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

function split2 {
    log "splitting"
    sudo iptables -t filter -I ISOLATION 1 -s 127.1.2.0/24 -d 127.2.2.0/24 -j DROP
    sudo iptables -t filter -I ISOLATION 1 -s 127.2.2.0/24 -d 127.1.2.0/24 -j DROP
    state2["intersite"]="shut down"
    [[ "$1" =~ ^[1-9][0-9]*$ ]] && sleep $1 && unsplit2
}

function unsplit2 {
    log "unsplitting"
    sudo iptables -t filter -D ISOLATION -s 127.1.2.0/24 -d 127.2.2.0/24 -j DROP
    sudo iptables -t filter -D ISOLATION -s 127.2.2.0/24 -d 127.1.2.0/24 -j DROP
    state2["intersite"]="opened"
}

function unreliable2 {
    log "^C to stop please"
    bash -c 'while true; do split2 $((10 + ($RANDOM % 10))); sleep $((10 + ($RANDOM % 10))); done'
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

function split3 {
    log "splitting"
    sudo iptables -t filter -I ISOLATION 1 -s 127.1.3.0/24 -d 127.2.3.0/24 -j DROP
    sudo iptables -t filter -I ISOLATION 1 -s 127.2.3.0/24 -d 127.1.3.0/24 -j DROP
    state3["intersite"]="shut down"
    [[ "$1" =~ ^[1-9][0-9]*$ ]] && sleep $1 && unsplit3
}

function unsplit3 {
    log "unsplitting"
    sudo iptables -t filter -D ISOLATION -s 127.1.3.0/24 -d 127.2.3.0/24 -j DROP
    sudo iptables -t filter -D ISOLATION -s 127.2.3.0/24 -d 127.1.3.0/24 -j DROP
    state3["intersite"]="opened"
}

function unreliable3 {
    log "^C to stop please"
    bash -c 'while true; do split3 $((1 + $RANDOM % 5)); sleep $((1 + $RANDOM % 5)); done'
    unsplit3
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
    sudo tc class add dev lo parent 1: classid 1:3 htb rate 200mbit # site 2 : flux cluster <-> cluster

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

    sudo tc qdisc add dev lo parent 1:3 handle 30: netem delay 5ms 1ms 5%  # Ajout d'un délai sur le flow 1:3 qui correspond à l'intersite.

    # ISOLATION will host failures.
    sudo iptables -t filter -N ISOLATION
    sudo iptables -t filter -A INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j ISOLATION
    sudo iptables -t filter -A OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j ISOLATION

    # MULTISITE creates the expected topography
    sudo iptables -t filter -N MULTISITE
    sudo iptables -t filter -A INPUT  -s 127.0.0.0/8 -d 127.0.0.0/8 -j MULTISITE
    sudo iptables -t filter -A OUTPUT -s 127.0.0.0/8 -d 127.0.0.0/8 -j MULTISITE
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
    java -cp 2.5/target/2.5-1.0-SNAPSHOT-jar-with-dependencies.jar Server25
}

function client2 {
    java -cp 2.5/target/2.5-1.0-SNAPSHOT-jar-with-dependencies.jar Client25
}

function servers3 {
    java -cp 3.10/target/3.10-1.0-SNAPSHOT-jar-with-dependencies.jar Server310
}

function client3 {
    java -cp 3.10/target/3.10-1.0-SNAPSHOT-jar-with-dependencies.jar Client310
}

export -f status2 shut2 open2 split2 unsplit2 unreliable2 servers2 client2
export -f status3 shut3 open3 split3 unsplit3 unreliable3 servers3 client3
export -f setup tear log compile monitor reset

echo "#####################################################################"
echo "usage: ___>>> THIS SCRIPT MUST BE SOURCED, NOT EXECUTED <<<___"
echo "On loading, this script will do 3 things:"
echo " 1. setup iptables and tc to create two 'sites' with a 5ms delay between them"
echo "    On the filter table of iptables, we create a chain ISOLATION and MULTISITE"
echo "    These tables are empty, the below commands will be implemented there."
echo "    One more chain named MONITOR is created so that you can witness which"
echo "    traffic is actually happening. Se for yourself with 'monitor'"
echo ""
echo "command list:"
echo ""
echo "tear    : reopens everything. You need a call to setup"
echo "          to use shut and open again"
echo ""
echo "setup   : prepare a set of rules to make shut and open"
echo "          to work as expected"
echo ""
echo "monitor : Shows a list of traffic between every ips defined by this tool"
echo "          see servers2 and servers3 for a list."
echo ""
echo "servers2: starts 4 servers on Hazelcast 2.5 with ips 127.2.[1-2].[1-2]"
echo "          127.2.1._ is site 1, 127.2.2._ is site 2"
echo "          127.2.1._ is site 1, 127.2.2._ is site 2"
echo ""
echo "servers3, client3, shut3, open3, split3, unsplit3 act on the 127.3.x.x nodes"
echo "servers2, client2, shut2, open2, split2, unsplit2 act on the 127.2.x.x nodes"
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
echo "client2 : gives state of nodes and intersite"
echo ""
echo "shut3, open3, split3, unsplit3 to act on the 127.3.x.x nodes"
