import com.hazelcast.config.*;
import com.hazelcast.core.Hazelcast;
import com.hazelcast.core.HazelcastInstance;
import lombok.AllArgsConstructor;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static java.lang.System.err;
import static java.lang.System.out;
import static java.lang.System.setProperty;
import static java.util.stream.Collectors.toList;

public class Server25 {

  @AllArgsConstructor
  public static final class Instance implements Comparable<Instance> {
    public final String name;
    public final String ip;
    public final int port;
    public final HazelcastInstance instance;

    public Instance(String name, String ip, int port) {
      this(name, ip, port, null);
    }

    public String toString() {
      return "node " + name + " (" + ip + ":" + port + ")";
    }

    public Instance with(HazelcastInstance instance) {
      return new Instance(name, ip, port, instance);
    }

    public String asAddress() {
      return ip + ":" + port;
    }

    @Override
    public int compareTo(Instance o) {
      return this.name.compareTo(o.name);
    }
  }

  public static void main(String[] args) throws Exception {
    setProperty("hazelcast.logging.type", "slf4j");
    Action.loop();
  }


  private enum Action {

    /**
     *
     */
    Kill("k[ill] x    : shuts server x, or all if none specified", "^ki?l?l?(.*)$") {
      @Override
      void execute(String args) {
        servers(args)
            .peek(i -> out.println("Killing server " + i.name))
            .map(i -> i.instance)
            .filter(Objects::nonNull)
            .forEach(HazelcastInstance::shutdown);
      }
    },

    /**
     *
     */
    Start("s[tart] x   : starts server x, or all if none specified", "^st?a?r?t?(.*)$") {
      @Override
      void execute(String args) {
        servers(args).forEach(this::one);
      }

      private void one(Instance inst) {
        final TcpIpConfig tcp = new TcpIpConfig().setEnabled(true);
        SERVERS.stream().map(Instance::asAddress).forEach(tcp::addMember);

        err.println("Starting instance " + inst);
        SERVERS.remove(inst);
        SERVERS.add(
            inst.with(Hazelcast.newHazelcastInstance(
                new Config()
                    .setNetworkConfig(new NetworkConfig()
                        .setInterfaces(new Interfaces().addInterface(inst.ip).setEnabled(true))
                        .setPort(inst.port)
                        .setJoin(new Join()
                            .setMulticastConfig(new MulticastConfig().setEnabled(false))
                            .setTcpIpConfig(tcp)
                        ))
                    .setPartitionGroupConfig(new PartitionGroupConfig()
                        .addMemberGroupConfig(new MemberGroupConfig().setInterfaces(Arrays.asList("127.1.2.1", "127.1.2.2")))
                        .addMemberGroupConfig(new MemberGroupConfig().setInterfaces(Arrays.asList("127.2.2.1", "127.2.2.2")))
                        .setGroupType(PartitionGroupConfig.MemberGroupType.CUSTOM)
                    )
                    .setProperty("hazelcast.socket.bind.any", "false")
                    .setProperty("hazelcast.heartbeat.interval.seconds", "1")
                    .setProperty("hazelcast.max.no.heartbeat.seconds", "10")
                    .setProperty("hazelcast.icmp.enabled", "true")
                    .setProperty("hazelcast.redo.log.threshold", "1")
                    //.setProperty("hazelcast.log.state", "true")
                    .setProperty("hazelcast.merge.first.run.delay.seconds", "1200")
                    .setProperty("hazelcast.merge.next.run.delay.seconds", "1200")
                    .setProperty("hazelcast.master.confirmation.interval.seconds", "1")
                    .setProperty("hazelcast.max.no.master.confirmation.seconds", "10")
                    .setProperty("hazelcast.member.list.publish.interval.seconds", "5")
            )));
      }
    },

    /**
     *
     */
    Restart("r[estart] x : restarts server x, or all if none specified", "^re?s?t?a?r?t?(.*)$") {
      @Override
      void execute(String args) {
        Kill.execute(args);
        Start.execute(args);
      }
    },

    /**
     *
     */
    List("l[ist] x    : lists status for x, or all if none specified", "^li?s?t?(.*)$") {
      @Override
      void execute(String args) {
        servers(args)
            .peek(i -> out.print("Server " + i + ": "))
            .map(i -> i.instance.getLifecycleService().isRunning())
            .forEach(s -> out.println(s ? " running" : " stopped"));
      }
    },

    /**
     *
     */
    Quit("q[uit]      : shuts everything down and quit", "^qu?i?t?$") {
      @Override
      void execute(String args) {
        System.exit(0);
      }
    },

    /**
     *
     */
    Help("h[elp]      : shows this message", "^h?(.*)$") {
      @Override
      void execute(String args) {
        if (args != null && !"".equals(args.trim())) {
          out.println("Could not understand " + args);
        }
        for (Action a : values()) {
          out.println(a.u);
        }
      }
    };

    private static final SortedSet<Instance> SERVERS = new TreeSet<>(Arrays.asList(
        new Instance("1", "127.1.2.1", 5701),
        new Instance("2", "127.1.2.2", 5702),
        new Instance("3", "127.2.2.1", 5703),
        new Instance("4", "127.2.2.2", 5704)
    ));

    private final Pattern p;
    private final String u;

    Action(String usage, String pattern) {
      p = Pattern.compile(pattern);
      u = usage;
    }

    abstract void execute(String args);

    static void match(String input) {

      for (Action a : values()) {
        Matcher m = a.p.matcher(input);
        if (m.matches()) {
          a.execute(m.groupCount() == 1 ? m.group(1) : "");
          break;
        }
      }

      out.print(">  ");
    }

    static void loop() throws IOException {

      Action.match("start");

      Action.Help.execute("");

      boolean stop = false;
      BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(System.in));
      while (!stop) {
        String value = bufferedReader.readLine();
        Action.match(value);
      }
    }

    private static Stream<Instance> servers(String s) {
      if (null != s && !"".equals(s = s.trim())) {
        List<String> nodes = Arrays.asList(s.split("\\s+"));
        return SERVERS.stream().filter(i -> nodes.contains(i.name)).collect(toList()).stream();
      } else {
        return SERVERS.stream().collect(toList()).stream();
      }
    }
  }

}
