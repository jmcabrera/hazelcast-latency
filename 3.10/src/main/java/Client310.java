import com.hazelcast.client.HazelcastClient;
import com.hazelcast.client.config.ClientConfig;
import com.hazelcast.client.config.ClientNetworkConfig;
import com.hazelcast.core.HazelcastInstance;
import com.hazelcast.core.IMap;

import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static java.lang.System.*;
import static java.util.concurrent.TimeUnit.SECONDS;

public class Client310 {

  public static void main(String[] args) throws InterruptedException {

    // https://docs.hazelcast.org/docs/2.5/manual/html-single/index.html#ConfigurationProperties
    setProperty("hazelcast.logging.type", "slf4j");
    setProperty("hazelcast.socket.client.bind.any", "false");
    setProperty("hazelcast.client.heartbeat.interval", "5000");
    setProperty("hazelcast.client.heartbeat.timeout", "1000");

    reconnect();

    int nb = 100;
    while (nb-- > 0) es.submit(Client310::runForever);

    long start = currentTimeMillis();

    Timer timer = new Timer("sampler", false);
    int sampling = 1000;
    timer.scheduleAtFixedRate(new TimerTask() {
      @Override
      public void run() {
        err.println((currentTimeMillis() - start) + "\t" + DONE.getAndSet(0));

        int dead = DEAD.getAndSet(0);
        if (10 < dead) {
          err.println(new Date() + ":  Failed " + dead + " times");
          reconnect();
        }
      }
    }, sampling, sampling);
  }

  private static final String BIG;

  static {
    // Building a 10ko string to simulate a ACS3 session.
    char[] content = new char[10_000];
    Arrays.fill(content, 'a');
    BIG = new String(content);
  }

  private static final ExecutorService es = Executors.newFixedThreadPool(10);

  private static final AtomicInteger DEAD = new AtomicInteger(0);

  private static volatile HazelcastInstance client;

  private static AtomicReference<IMap> map = new AtomicReference<>();

  private static void runForever() {
    while (true) {
      try {
        Thread.sleep(5);
        map.get().put(UUID.randomUUID(), BIG, 10, SECONDS);
        DONE.incrementAndGet();
      } catch (Throwable t) {
        DEAD.incrementAndGet();
      }
    }
  }

  private static synchronized void reconnect() {
    try {
      err.println("reconnecting");
      if (null != client) client.getLifecycleService().terminate();
      client = HazelcastClient.newHazelcastClient(
          new ClientConfig()
              .setNetworkConfig(
                  new ClientNetworkConfig()
                      .addAddress("127.3.1.1:5701", "127.3.1.2:5702")
                      .setSmartRouting(false)));
      map.set(client.getMap("customers"));
      DEAD.set(0);
    } catch (Throwable e) {
      e.printStackTrace();
    }
  }

  private static final AtomicInteger DONE = new AtomicInteger(0);

}
