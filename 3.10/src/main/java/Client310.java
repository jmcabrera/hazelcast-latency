import com.hazelcast.client.HazelcastClient;
import com.hazelcast.client.HazelcastClientOfflineException;
import com.hazelcast.client.config.ClientConfig;
import com.hazelcast.client.config.ClientConnectionStrategyConfig;
import com.hazelcast.core.HazelcastInstance;
import com.hazelcast.core.IMap;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.val;

import java.util.Arrays;
import java.util.Date;

import static java.lang.System.err;
import static java.lang.System.setProperty;

public class Client310 {

  public static void main(String[] args) throws InterruptedException {

    // https://docs.hazelcast.org/docs/2.5/manual/html-single/index.html#ConfigurationProperties
    setProperty("hazelcast.logging.type", "slf4j");
//    setProperty("hazelcast.redo.log.threshold", "3");
//    setProperty("hazelcast.redo.giveup.threshold", "10");
//    setProperty("hazelcast.max.operation.timeout", "1000");
    setProperty("hazelcast.client.heartbeat.interval", "10000");
    setProperty("hazelcast.client.heartbeat.timeout", "2000");
    setProperty("hazelcast.health.monitoring.level", "NOISY");

//    setProperty("hazelcast.client.invocation.timeout.seconds", "2000");

    val clientConfig = new ClientConfig();
    clientConfig.getNetworkConfig()
        .addAddress("127.3.1.1:5701", "127.3.1.2:5701")
//        .setConnectionAttemptPeriod(100)
//        .setConnectionAttemptLimit(0)
//        .setConnectionTimeout(500)
    ;
    clientConfig
        .setSmartRouting(false)
        .getConnectionStrategyConfig().setReconnectMode(ClientConnectionStrategyConfig.ReconnectMode.ASYNC).setAsyncStart(true);

    HazelcastInstance client = null;
    while (true) {
      try {
        if (null == client) client = reconnect(clientConfig);

        Thread.sleep(1000);

        final HazelcastInstance c = client;
        val size = timed(() -> {
          IMap<Object, Object> map = c.getMap("customers");
          map.put("" + new Object(), "" + new Object());
          return map.size();
        });

        err.println(new Date() + ": Map Size:" + size.getValue() + " (" + size.getDuration() + ")");

      } catch (HazelcastClientOfflineException hcoe) {
        err.println("client offline, retrying");
      } catch (Throwable t) {
        client = null;
        err.println("Error : " + t.getMessage());
      }
    }
  }


  private static HazelcastInstance reconnect(ClientConfig config) throws InterruptedException {
    val t = timed(() -> {
      err.println("connecting new client");
      HazelcastInstance client = HazelcastClient.newHazelcastClient(config);
      return client;
    });
    err.println("reconnection took " + t.getDuration());
    return t.getValue();
  }

  private static <E extends Exception> float timed(RunnableEx<E> run) throws E {
    long dur = System.nanoTime();
    run.run();
    return (System.nanoTime() - dur) / 1000000f;
  }

  private static <S, E extends Exception> Timed<S> timed(SupplierEx<S, E> run) throws E {
    long dur = System.nanoTime();
    S s = run.get();
    return new Timed<>(s, (System.nanoTime() - dur) / 1000000f);
  }

  @Data
  @AllArgsConstructor
  private static final class Timed<A> {
    private final A value;
    private final float duration;

  }

  private interface SupplierEx<S, E extends Exception> {
    S get() throws E;
  }

  private interface RunnableEx<E extends Exception> {
    void run() throws E;
  }

}
