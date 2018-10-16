import com.hazelcast.client.ClientConfig;
import com.hazelcast.client.HazelcastClient;
import com.hazelcast.config.*;
import com.hazelcast.core.*;
import lombok.AllArgsConstructor;
import lombok.val;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.List;

import static java.lang.System.err;
import static java.lang.System.setProperty;

public class Server25 {

  @AllArgsConstructor
  public static final class Address {
    public final String ip;
    public final int port;

    public String toString() {
      return ip + ":" + port;
    }
  }

  public static void main(String[] args) throws Exception {

    // https://docs.hazelcast.org/docs/2.5/manual/html-single/index.html#ConfigurationProperties
    setProperty("hazelcast.logging.type", "slf4j");
//    setProperty("hazelcast.redo.log.threshold", "3");
//    setProperty("hazelcast.redo.giveup.threshold", "10");
//    setProperty("hazelcast.max.operation.timeout", "500");
    setProperty("hazelcast.max.no.master.confirmation.seconds", "3");

    List<HazelcastInstance> instances = new ArrayList<>();

    val addresses = Arrays.asList(
        new Address("127.2.1.1", 5701),
        new Address("127.2.1.2", 5701),
        new Address("127.2.2.1", 5701),
        new Address("127.2.2.2", 5701)
    );

    val tcp = new TcpIpConfig().setEnabled(true);
    addresses.stream().map(Object::toString).forEach(tcp::addMember);
    tcp.setConnectionTimeoutSeconds(1);

    for (Address address : addresses) {
      err.println("Starting instance " + address);

      NetworkConfig join = new NetworkConfig()
          .setInterfaces(new Interfaces().addInterface(address.ip).setEnabled(true))
          .setPort(address.port)
          .setJoin(new Join()
              .setMulticastConfig(new MulticastConfig().setEnabled(false))
              .setTcpIpConfig(tcp)
          );
      join.setPublicAddress(address.ip);

      Config config = new Config().setNetworkConfig(join);
      config.setProperty("hazelcast.socket.bind.any", "false");
      config.setProperty("hazelcast.heartbeat.interval.seconds", "3");
      config.setProperty("hazelcast.max.no.heartbeat.seconds", "20");
      config.setProperty("hazelcast.merge.first.run.delay.seconds", "5");
      config.setProperty("hazelcast.merge.next.run.delay.seconds", "5");
      config.setProperty("hazelcast.master.confirmation.interval.seconds", "10");
      config.setProperty("hazelcast.max.no.master.confirmation.seconds", "20");
      config.setProperty("hazelcast.member.list.publish.interval.seconds", "10");
      val h = Hazelcast.newHazelcastInstance(config);

      h.getCluster().addMembershipListener(new MembershipListener() {

        private final Address a = address;

        @Override
        public void memberAdded(MembershipEvent membershipEvent) {
          err.println("from " + a + ":  " + membershipEvent);
        }

        @Override
        public void memberRemoved(MembershipEvent membershipEvent) {
          err.println("from " + a + ":" + membershipEvent);
        }
      });

      instances.add(h);
    }

    try {
      Object o = new Object();
      synchronized (o) {
        o.wait();
      }
    } catch (Throwable t) {
      t.printStackTrace();
    } finally {
      instances.stream().parallel().forEach(HazelcastInstance::shutdown);
    }


  }

}
