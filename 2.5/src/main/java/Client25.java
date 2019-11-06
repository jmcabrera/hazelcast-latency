import com.hazelcast.client.ClientConfig;
import com.hazelcast.client.HazelcastClient;
import com.hazelcast.core.HazelcastInstance;
import com.hazelcast.core.IMap;

import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static java.lang.System.*;

public class Client25 {

  public static void main(String[] args) {

    // https://docs.hazelcast.org/docs/2.5/manual/html-single/index.html#ConfigurationProperties
    setProperty("hazelcast.logging.type", "slf4j");
    setProperty("hazelcast.socket.client.bind.any", "false");

    reconnect();

    int nb = 100;
    while (nb-- > 0) es.submit(Client25::runForever);

    long start = currentTimeMillis();

    Timer timer = new Timer("sampler", false);
    int sampling = 5000;
    timer.scheduleAtFixedRate(new TimerTask() {
      @Override
      public void run() {
        int done = DONE.getAndSet(0);
        err.println((currentTimeMillis() - start) + "\t" + done + "\t" + SIZE.get());

        int dead = DEAD.getAndSet(0);
        if (0 == done) {
          err.println(new Date() + ": client inactive, reconnecting");
          reconnect();
        }
        if(10 < dead) {
          err.println(new Date() + ":  Failed " + dead + " times");
          reconnect();
        }
      }
    }, sampling, sampling);
  }

  private static final String BIG;

  static {
    // Building a 10ko string to simulate a ACS3 session.
    Random r = new Random();
    char[] content = new char[10_000];
    Arrays.fill(content, (char) ('a' + r.nextInt(26)));
    BIG = new String(content);
  }

  private static final ExecutorService es = Executors.newFixedThreadPool(10);

  private static final AtomicInteger DEAD = new AtomicInteger(0);

  private static volatile HazelcastInstance client;

  private static AtomicReference<IMap> map = new AtomicReference<>();

  private static void runForever() {
    while (true) {
      try {
//        Thread.sleep(5);
//        map.get().put(UUID.randomUUID(), BIG, 10, SECONDS);
        Thread.sleep(20);
        map.get().put(UUID.randomUUID(), BIG);
        DONE.incrementAndGet();
        SIZE.set(map.get().size());
      } catch (Throwable t) {
        DEAD.incrementAndGet();
      }
    }
  }

  private synchronized static void reconnect() {
    try {
      err.println("reconnecting");
      if (null != client) client.getLifecycleService().kill();
      client = HazelcastClient.newHazelcastClient(
          new ClientConfig()
              .addAddress("127.1.2.1:5701", "127.1.2.2:5702")
              .setConnectionTimeout(2000));
      map.set(client.getMap("customers"));
      DEAD.set(0);
    } catch (Throwable e) {
      e.printStackTrace();
    }
  }

  private static final AtomicInteger DONE = new AtomicInteger(0);
  private static final AtomicInteger SIZE = new AtomicInteger(0);

}
